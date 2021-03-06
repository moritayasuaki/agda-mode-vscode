open Belt

// abstraction of a panel
module Panel: {
  type t
  // constructor / destructor
  let make: (string, string) => t
  let destroy: t => unit
  // messaging
  let send: (t, string) => Promise.t<bool>
  let recv: (t, Js.Json.t => unit) => VSCode.Disposable.t
  // events
  let onDestroyed: (t, unit => unit) => VSCode.Disposable.t
  // methods
  let reveal: t => unit
  let focus: t => unit

  // move the panel around
  let moveToBottom: unit => unit
  // let moveToLeft: unit => unit
} = {
  type t = VSCode.WebviewPanel.t

  let makeHTML = (webview, extensionPath) => {
    let extensionUri = VSCode.Uri.file(extensionPath)
    // generates gibberish
    let nonce = {
      let text = ref("")
      let charaterSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      let cardinality = Js.String.length(charaterSet)
      for _ in 0 to 32 {
        text :=
          text.contents ++
          Js.String.charAt(
            Js.Math.floor(Js.Math.random() *. float_of_int(cardinality)),
            charaterSet,
          )
      }
      text.contents
    }

    let scriptUri =
      VSCode.Webview.asWebviewUri(
        webview,
        VSCode.Uri.joinPath(extensionUri, ["dist", "view.bundle.js"]),
      )->VSCode.Uri.toString

    let cspSourceUri = VSCode.Webview.cspSource(webview)

    let styleUri =
      VSCode.Webview.asWebviewUri(
        webview,
        VSCode.Uri.joinPath(extensionUri, ["dist", "style.css"]),
      )->VSCode.Uri.toString

    let codiconsUri =
      VSCode.Webview.asWebviewUri(
        webview,
        VSCode.Uri.joinPath(extensionUri, ["dist", "codicon.css"]),
      )->VSCode.Uri.toString

    let codiconsFontUri =
      VSCode.Webview.asWebviewUri(
        webview,
        VSCode.Uri.joinPath(extensionUri, ["dist", "codicon.ttf"]),
      )->VSCode.Uri.toString

    // Content-Security-Policy
    let defaultSrc = "default-src 'none'; "
    let scriptSrc = "script-src 'nonce-" ++ nonce ++ "'; "
    let styleSrc = "style-src " ++ cspSourceUri ++ " " ++ styleUri ++ " " ++ codiconsUri ++ "; "
    let fontSrc = "font-src " ++ codiconsFontUri ++ "; "
    let scp = defaultSrc ++ fontSrc ++ scriptSrc ++ styleSrc

    j`
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,shrink-to-fit=no">
        <meta name="theme-color" content="#000000">

        <!--
					Use a content security policy to only allow loading images from https or from our extension directory,
					and only allow scripts that have a specific nonce.
				-->
        <meta http-equiv="Content-Security-Policy" content="$scp">

        <title>React App</title>
        <link href="$styleUri"    rel="stylesheet" type="text/css" >
        <link href="$codiconsUri" rel="stylesheet" />
      </head>
      <body>
        <noscript>You need to enable JavaScript to run this app.</noscript>
        <div id="root"></div>
        <script nonce="$nonce" src="$scriptUri"></script>
      </body>
      </html>
    `
  }

  let make = (title, extensionPath) => {
    let distPath = Node.Path.join2(extensionPath, "dist")
    let panel = VSCode.Window.createWebviewPanel(
      "panel",
      title,
      {"preserveFocus": true, "viewColumn": 3},
      // None,
      Some(
        VSCode.WebviewAndWebviewPanelOptions.make(
          ~enableScripts=true,
          // So that the view don't get wiped out when it's not in the foreground
          ~retainContextWhenHidden=true,
          // And restrict the webview to only loading content from our extension's `media` directory.
          ~localResourceRoots=[VSCode.Uri.file(distPath)],
          (),
        ),
      ),
    )

    let html = makeHTML(VSCode.WebviewPanel.webview(panel), extensionPath)
    panel->VSCode.WebviewPanel.webview->VSCode.Webview.setHtml(html)

    panel
  }

  let destroy = VSCode.WebviewPanel.dispose

  let send = (panel, message) =>
    panel->VSCode.WebviewPanel.webview->VSCode.Webview.postMessage(message)

  let recv = (panel, callback) =>
    panel->VSCode.WebviewPanel.webview->VSCode.Webview.onDidReceiveMessage(callback)

  let onDestroyed = (panel, callback) => panel->VSCode.WebviewPanel.onDidDispose(callback)

  let reveal = panel => panel->VSCode.WebviewPanel.reveal(~preserveFocus=true, ())
  let focus = panel => panel->VSCode.WebviewPanel.reveal()

  // let moveToLeft = () => {
  //   open VSCode.Commands
  //   executeCommand(
  //     #setEditorLayout({
  //       orientation: 0,
  //       groups: {
  //         open Layout
  //         [sized({groups: [simple], size: 0.5}), sized({groups: [simple], size: 0.5})]
  //       },
  //     }),
  //   )->ignore
  // }

  let moveToBottom = () => {
    open VSCode.Commands
    executeCommand(
      #setEditorLayout({
        orientation: 1,
        groups: {
          open Layout
          [sized({groups: [simple], size: 0.7}), sized({groups: [simple], size: 0.3})]
        },
      }),
    )->ignore
  }
}

// a thin layer on top of Panel
module type PanelController = {
  type t

  let make: string => t
  let destroy: t => unit

  let sendEvent: (t, View.EventToView.t) => Promise.t<unit>
  let sendRequest: (t, View.Request.t, View.Response.t => Promise.t<unit>) => Promise.t<unit>
  let onEvent: (t, View.EventFromView.t => unit) => VSCode.Disposable.t

  let onceDestroyed: t => Promise.t<unit>

  let reveal: t => unit
  let focus: t => unit
}

module PanelController: PanelController = {
  type status =
    | Initialized
    | Uninitialized(
        array<(View.Request.t, View.ResponseOrEventFromView.t => unit)>,
        array<View.EventToView.t>,
      )

  type t = {
    panel: Panel.t,
    onResponse: Chan.t<View.Response.t>,
    onEvent: Chan.t<View.EventFromView.t>,
    subscriptions: array<VSCode.Disposable.t>,
    mutable status: status,
  }

  // messaging
  let send = (view, requestOrEvent) =>
    switch view.status {
    | Uninitialized(queuedRequests, queuedEvents) =>
      open View.RequestOrEventToView
      switch requestOrEvent {
      | Request(req) =>
        let (promise, resolve) = Promise.pending()
        Js.Array.push(
          (
            req,
            x =>
              switch x {
              | View.ResponseOrEventFromView.Event(_) => resolve(None)
              | Response(res) => resolve(Some(res))
              },
          ),
          queuedRequests,
        )->ignore
        promise
      | Event(event) =>
        Js.Array.push(event, queuedEvents)->ignore
        Promise.resolved(None)
      }
    | Initialized =>
      open View.RequestOrEventToView
      let stringified = Js.Json.stringify(View.RequestOrEventToView.encode(requestOrEvent))

      switch requestOrEvent {
      | Request(_) =>
        let promise = view.onResponse->Chan.once
        view.panel
        ->Panel.send(stringified)
        ->Promise.flatMap(_ => promise)
        ->Promise.map(res => Some(res))
      | Event(_) => view.panel->Panel.send(stringified)->Promise.map(_ => None)
      }
    }

  let sendEvent = (view, event) =>
    send(view, View.RequestOrEventToView.Event(event))->Promise.map(_ => ())
  let sendRequest = (view, request, callback) =>
    send(view, View.RequestOrEventToView.Request(request))->Promise.flatMap(x =>
      switch x {
      | None => Promise.resolved()
      | Some(response) => callback(response)
      }
    )

  let onEvent = (view, callback) =>
    // Handle events from the webview
    view.onEvent->Chan.on(callback)->VSCode.Disposable.make

  let make = extensionPath => {
    let view = {
      panel: Panel.make("Agda", extensionPath),
      subscriptions: [],
      onResponse: Chan.make(),
      onEvent: Chan.make(),
      status: Uninitialized([], []),
    }

    // Move the created panel to the bottom row
    switch Config.getPanelMountingPosition() {
    | Bottom => Panel.moveToBottom()
    | Right => ()
    }

    // on message
    // relay Webview.onDidReceiveMessage => onResponse or onEvent
    view.panel
    ->Panel.recv(json =>
      switch View.ResponseOrEventFromView.decode(json) {
      | Response(res) => view.onResponse->Chan.emit(res)
      | Event(ev) => view.onEvent->Chan.emit(ev)
      | exception e => Js.log2("[ panic ][ Webview.onDidReceiveMessage JSON decode error ]", e)
      }
    )
    ->Js.Array.push(view.subscriptions)
    ->ignore

    // on destroy
    view.panel
    ->Panel.onDestroyed(() => view.onEvent->Chan.emit(Destroyed))
    ->Js.Array.push(view.subscriptions)
    ->ignore

    // when initialized, send the queued Requests & Events
    view.onEvent
    ->Chan.on(x =>
      switch x {
      | Initialized =>
        switch view.status {
        | Uninitialized(queuedRequests, queuedEvents) =>
          view.status = Initialized
          queuedRequests->Belt.Array.forEach(((req, resolve)) =>
            send(view, View.RequestOrEventToView.Request(req))->Promise.get(x =>
              switch x {
              | None => ()
              | Some(res) => resolve(View.ResponseOrEventFromView.Response(res))
              }
            )
          )
          queuedEvents->Belt.Array.forEach(event =>
            send(view, View.RequestOrEventToView.Event(event))->ignore
          )
        | Initialized => ()
        }
      | _ => ()
      }
    )
    ->VSCode.Disposable.make
    ->Js.Array.push(view.subscriptions)
    ->ignore

    view
  }

  let destroy = view => {
    // if we invoke `view.panel->WebviewPanel.dispose` first,
    // this would trigger `View.ResponseOrEventFromView.Event(Destroyed)`
    // and in turns would trigger this function AGAIN

    // destroy the chan first, to prevent the aforementioned from happening
    view.onResponse->Chan.destroy
    view.onEvent->Chan.destroy
    view.panel->Panel.destroy
    view.subscriptions->Belt.Array.forEach(VSCode.Disposable.dispose)
  }

  // resolves the returned promise once the view has been destroyed
  let onceDestroyed = (view: t): Promise.t<unit> => {
    let (promise, resolve) = Promise.pending()

    let disposable = view.onEvent->Chan.on(response =>
      switch response {
      | Destroyed => resolve()
      | _ => ()
      }
    )

    promise->Promise.tap(disposable)
  }

  // show/focus
  let reveal = view => view.panel->Panel.reveal
  let focus = view => view.panel->Panel.focus
}

module type Controller = {
  type t
  // methods
  let activate: string => unit
  let deactivate: unit => unit
  let isActivated: unit => bool

  let sendRequest: (View.Request.t, View.Response.t => Promise.t<unit>) => Promise.t<unit>
  let sendEvent: View.EventToView.t => Promise.t<unit>
  let onEvent: (View.EventFromView.t => unit) => VSCode.Disposable.t

  let reveal: unit => unit
  let focus: unit => unit
}
module Controller: Controller = {
  type t = ref<option<PanelController.t>>
  let panel = ref(None)

  let sendRequest = (req, callback) =>
    switch panel.contents {
    | None => Promise.resolved()
    | Some(panel) => PanelController.sendRequest(panel, req, callback)
    }
  let sendEvent = event =>
    switch panel.contents {
    | None => Promise.resolved()
    | Some(panel) => PanelController.sendEvent(panel, event)
    }

  let onEvent = callback =>
    switch panel.contents {
    | None => VSCode.Disposable.make(() => ())
    | Some(panel) => panel->PanelController.onEvent(callback)
    }

  let activate = extensionPath => {
    let instance = PanelController.make(extensionPath)
    panel := Some(instance)
    // free the handle when the view has been forcibly destructed
    PanelController.onceDestroyed(instance)->Promise.get(() => {
      panel := None
    })
  }

  let deactivate = () => {
    panel.contents->Option.forEach(PanelController.destroy)
    panel := None
  }

  let isActivated = () => panel.contents->Option.isSome

  let reveal = () => panel.contents->Option.forEach(PanelController.reveal)
  let focus = () => panel.contents->Option.forEach(PanelController.focus)
}

include Controller

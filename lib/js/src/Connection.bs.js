// Generated by BUCKLESCRIPT, PLEASE EDIT WITH CARE
'use strict';

var Json = require("@glennsl/bs-json/lib/js/src/Json.bs.js");
var Curry = require("bs-platform/lib/js/curry.js");
var $$Promise = require("reason-promise/lib/js/src/js/promise.js");
var Belt_Option = require("bs-platform/lib/js/belt_Option.js");
var Caml_option = require("bs-platform/lib/js/caml_option.js");
var Process$AgdaMode = require("agda-mode/lib/js/src/Process.bs.js");
var Caml_chrome_debugger = require("bs-platform/lib/js/caml_chrome_debugger.js");
var Event$AgdaModeVscode = require("./Util/Event.bs.js");

function toString(e) {
  switch (e.tag | 0) {
    case /* PathSearch */0 :
        return Curry._1(Process$AgdaMode.PathSearch.$$Error.toString, e[0]);
    case /* Validation */1 :
        return Curry._1(Process$AgdaMode.Validation.$$Error.toString, e[0]);
    case /* Process */2 :
        return Process$AgdaMode.$$Error.toString(e[0]);
    
  }
}

var $$Error = {
  toString: toString
};

function isConnected(connection) {
  return Curry._1(connection.process.isConnected, undefined);
}

function disconnect(connection) {
  return Curry._1(connection.process.disconnect, undefined);
}

function wire(connection) {
  var unfinishedMsg = {
    contents: undefined
  };
  Curry._1(connection.process.emitter.on, (function (data) {
          if (data.tag) {
            return Curry._1(connection.emitter.emit, /* Error */Caml_chrome_debugger.variant("Error", 1, [/* Process */Caml_chrome_debugger.variant("Process", 2, [data[0]])]));
          }
          var data$1 = data[0];
          var unfinished = unfinishedMsg.contents;
          var augmented = unfinished !== undefined ? unfinished + data$1 : data$1;
          var result = Json.parse(augmented);
          if (result !== undefined) {
            unfinishedMsg.contents = undefined;
            Curry._1(connection.emitter.emit, /* Ok */Caml_chrome_debugger.variant("Ok", 0, [Caml_option.valFromOption(result)]));
            return ;
          } else {
            unfinishedMsg.contents = augmented;
            return ;
          }
        }));
  
}

function getGCLPath(fromConfig) {
  var storedPath = Belt_Option.mapWithDefault(Curry._1(fromConfig, undefined), "", (function (prim) {
          return prim.trim();
        }));
  if (storedPath === "" || storedPath === ".") {
    return $$Promise.mapError($$Promise.mapOk(Process$AgdaMode.PathSearch.run("gcl"), (function (prim) {
                      return prim.trim();
                    })), (function (e) {
                  return /* PathSearch */Caml_chrome_debugger.variant("PathSearch", 0, [e]);
                }));
  } else {
    return $$Promise.resolved(/* Ok */Caml_chrome_debugger.variant("Ok", 0, [storedPath]));
  }
}

function setGCLPath(toConfig, path) {
  return $$Promise.map(Curry._1(toConfig, path), (function (param) {
                return /* Ok */Caml_chrome_debugger.variant("Ok", 0, [path]);
              }));
}

function validateGCLPath(path) {
  return $$Promise.mapError(Process$AgdaMode.Validation.run(path + " --help", (function (output) {
                    if (/^GCL/.test(output)) {
                      return /* Ok */Caml_chrome_debugger.variant("Ok", 0, [path]);
                    } else {
                      return /* Error */Caml_chrome_debugger.variant("Error", 1, [path]);
                    }
                  })), (function (e) {
                return /* Validation */Caml_chrome_debugger.variant("Validation", 1, [e]);
              }));
}

function make(fromConfig, toConfig) {
  return $$Promise.tapOk($$Promise.mapOk($$Promise.flatMapOk($$Promise.flatMapOk(getGCLPath(fromConfig), validateGCLPath), (function (param) {
                        return setGCLPath(toConfig, param);
                      })), (function (path) {
                    var $$process = Process$AgdaMode.make(path, []);
                    return {
                            path: path,
                            process: $$process,
                            emitter: Event$AgdaModeVscode.make(undefined)
                          };
                  })), wire);
}

function send(request, connection) {
  var promise = Curry._1(connection.emitter.once, undefined);
  var result = Curry._1(connection.process.send, request);
  if (result.tag) {
    return $$Promise.resolved(/* Error */Caml_chrome_debugger.variant("Error", 1, [/* Process */Caml_chrome_debugger.variant("Process", 2, [result[0]])]));
  } else {
    return promise;
  }
}

var Process;

exports.Process = Process;
exports.$$Error = $$Error;
exports.isConnected = isConnected;
exports.disconnect = disconnect;
exports.wire = wire;
exports.getGCLPath = getGCLPath;
exports.setGCLPath = setGCLPath;
exports.validateGCLPath = validateGCLPath;
exports.make = make;
exports.send = send;
/* Promise Not a pure module */
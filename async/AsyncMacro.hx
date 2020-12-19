package async;


#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import sys.io.File;

using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;

using async.AsyncMacroUtils;


class AsyncMacro {
  public static var asyncPlaceholder = "%asyncPlaceholder%";

  macro public static function build(): Array<Field> {
    registerFinishCallback();
    var fields = Context.getBuildFields();
    for (field in fields) {
      var meta = field.meta;
      if (meta != null) {
        for (data in meta) {
          if (data.name == "async") {
            switch field.kind {
              case FFun(f):
                f.expr = addAsyncMarker(f.expr);
                switch (f.expr.expr) {
                  case EBlock(exprs):
                    for (expr in exprs) {
                      switch (expr.expr) {
                        case EBlock(exprs):
                          for (expr in exprs) {
                            switch (expr.expr) {
                              case EReturn(e):
                                if (e != null) {
                                  switch (e.expr) {
                                    case EMeta(s, metaE):
                                      if (s.name == "await") {
                                        e.expr = convertToAwait(e);
                                      }
                                    default:
                                      "";
                                  }
                                }
                              default:
                                continue;
                            }
                          }
                        default:
                          continue;
                      }
                    }
                  default:
                    continue;
                }
              default:
                throw "async can be applied only to a function";
            }
          }
        }
      }
    }
    return fields;
  }

  public static function onFinishCallback() {
    var sourceCodePath = Compiler.getOutput();
    var target = Context.definedValue("target.name");
    var regex: EReg;
    if (target == "js") {
      regex = new EReg('((function|\\w*)?\\s*\\([^()]*\\)\\s*\\{\\s*?)${asyncPlaceholder};\n\\s*', "gm");
    } else if (target == "python") {
      regex = new EReg('(def .*?\\(.*?\\):\\s*)${asyncPlaceholder}\n\\s*', "gm");
    }
    var sourceCode = File.getContent(sourceCodePath);
    sourceCode = regex.replace(sourceCode, "async $1");
    File.saveContent(sourceCodePath, sourceCode);
  }

  public static function registerFinishCallback() {
    Context.onAfterGenerate(onFinishCallback);
  }

  public static function getPlatformFunctionBody(e: Expr) {
    return switch Context.definedValue("target.name") {
      case "js":
        macro @:pos(e.pos) {
          std.js.Syntax.code("%asyncPlaceholder%");
          ${e};
        };
      case "python":
        macro @:pos(e.pos) {
          std.python.Syntax.code("%asyncPlaceholder%");
          ${e};
        };
      default:
        e;
    }
  }

  public static function addAsyncMarker(e: Expr) {
		return switch e.expr {
      case EBlock(exprs):
        getPlatformFunctionBody(e);
      default:
        throw "Invalid expression";
		}
  }

  public static function convertToAwait(e: Expr) {
    return switch (e.expr) {
      case EMeta(s, metaE):
        (macro AsyncMacroUtils.await(${metaE})).expr;
      default:
        throw "Invalid expression";
    }
  }
}
#end

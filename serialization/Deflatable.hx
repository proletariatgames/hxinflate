package serialization;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// have a build macro that adds @keep and @rtti and checks @version
// - potential optimizations:
//  - no rtti, add a static method that returns version info
//  - keep on fields and hxSerialize / hxUnserialize instead of entire class

@:autoBuild(serialization.DeflatableBuild.build())
interface Deflatable
{
}

class DeflatableBuild
{
  public inline static var VERSION_FN = "___deflatable_version";

  #if macro
  public static macro function build() : Array<Field> {
    var localClass = Context.getLocalClass().get();
    var fields = Context.getBuildFields();

    localClass.meta.add(":keepSub", [], localClass.pos);

    var versionExpr = macro 0;
    var version = Lambda.find(localClass.meta.get(), function (x) { return x.name == "version"; });
    if (version != null) {
      if (version.params.length != 1) {
        Context.error("Deflatable version require one param", localClass.pos);
      }
      versionExpr = version.params[0];
      // Check the type on this parameter
      switch (versionExpr.expr) {
      case EConst(CInt(v)):
      default: Context.error("version parameter must be a constant integer", versionExpr.pos);
      }
    }

    var versionFn = {
      ret : TPath({ name : "Int", pack : [], params : [] }),
      params : [],
      args : [],
      expr : macro {
        return $versionExpr;
      },
    };

    fields.push({
      pos : localClass.pos,
      name : VERSION_FN,
      meta : [],
      kind : FFun(versionFn),
      doc : null,
      access : [ APublic, AStatic ]
    });

    return fields;
  }

  #end
}

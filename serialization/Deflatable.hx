/*
 * Copyright (C)2005-2013 Haxe Foundation
 * Portions Copyright (C) 2013 Proletariat, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

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

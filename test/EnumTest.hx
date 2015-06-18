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

import nodeunit.TestCase;
import serialization.*;

enum TestEnumA {
  Value_0;
  Value_1(zero:Int);
}

/*
// ENUM_B_VERSION_0
enum TestEnumB {
  Value_0;
  Value_1(zero:Int);
}
*/

enum TestEnumB {
  Value_0(added:Int);
  Value_1(zero:Int);
}

@version(1)
class TestEnumB_deflatable implements Deflatable {
  public static function _upgrade_enum(version:Int, data:{constructor:String, params:Array<Dynamic>}) {
    if (version < 1) {
      switch(data.constructor) {
        case 'Value_0': data.params = [1000];
      }
    }
  }
}

/*
// ENUM_C_VERSION_0
enum TestEnumC {
  Value_0;
  Value_1(zero:Int);
}
*/

enum TestEnumC {
  Value_A;
  Value_1(zero:Int);
}

@version(1)
class TestEnumC_deflatable implements Deflatable {
  public static function _upgrade_enum(version:Int, data:{constructor:String, params:Array<Dynamic>}) {
    if (version < 1) {
      switch(data.constructor) {
        case 'Value_0': data.constructor = 'Value_A';
      }
    }
  }
}

/*
// ENUM_D_VERSION_0
enum TestEnumD {
  Value_0;
  Value_1(zero:Int);
}
*/

enum TestEnumD {
  Value_0;
  Value_1;
}

@version(1)
class TestEnumD_deflatable implements Deflatable {
  public static function _upgrade_enum(version:Int, data:{constructor:String, params:Array<Dynamic>}) {
    if (version < 1) {
      switch(data.constructor) {
        case 'Value_1': data.params = null;
      }
    }
  }
}


class EnumTest {

  static function traceBlob(v : Dynamic) : Void {
    trace(Deflater.run(v));
  }

  @test static public function test_deserializeEnumSameVersion(test:TestCase) : Void {
    var enumA:TestEnumA = Value_0;
    var deflatedA = Deflater.run(enumA);
    var inflatedA:TestEnumA = Inflater.run(deflatedA);
    test.ok(inflatedA.match(Value_0));
    test.strictEqual(enumA, inflatedA);
  }

  public static var ENUM_B_VERSION_0 = "ZVER3n_Y9:TestEnumB:0:2:Y7:Value_0:0:Y7:Value_1:1:zg";
  @test static public function test_upgradeAddParam(test:TestCase) : Void {
    var upgradedEnumB:TestEnumB = Inflater.run(ENUM_B_VERSION_0);
    test.ok(upgradedEnumB.match(Value_0(_)));
    switch(upgradedEnumB) {
      case Value_0(added): test.strictEqual(1000, added);
      default: test.ok(false);
    }
  }

  public static var ENUM_C_VERSION_0 = "ZVER3n_Y9:TestEnumC:0:2:Y7:Value_0:0:Y7:Value_1:1:zg";
  @test static public function test_upgradeRenameConstructor(test:TestCase) : Void {
    var upgradedEnumC:TestEnumC = Inflater.run(ENUM_C_VERSION_0);
    test.ok(upgradedEnumC.match(Value_A));
  }

  public static var ENUM_D_VERSION_0 = "ZVER3n_Y9:TestEnumD:0:2:Y7:Value_0:0:Y7:Value_1:1:i1i123g";
  @test static public function test_upgradeRemoveParameter(test:TestCase) : Void {
    var upgradedEnumD:TestEnumD = Inflater.run(ENUM_D_VERSION_0);
    test.ok(upgradedEnumD.match(Value_1));
  }

}

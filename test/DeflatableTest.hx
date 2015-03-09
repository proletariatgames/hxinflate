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

class TestDeflatableNoVersionA implements Deflatable {}

@version(3) class TestDeflatableNoVersionB extends TestDeflatableNoVersionA {}

@version(2) class TestDeflatableMixedVersionC extends TestDeflatableNoVersionB {}

@version(1) class TestDeflatableVersionA implements Deflatable {}

class DeflatableTest {
  public function new() { }

  static function getVersionByReflection(cls:Class<Dynamic>) : Int {
    return Reflect.callMethod(cls, Reflect.field(cls, "___deflatable_version"), []);
  }

  @test static public function test_deflatableVersionForNoSpecifiedVersionIsZero(test:TestCase) : Void {
    test.strictEqual(TestDeflatableNoVersionA.___deflatable_version(), 0);
    test.strictEqual(getVersionByReflection(TestDeflatableNoVersionA), 0);
  }

  @test static public function test_deflatableVersionForSpecifiedVersionIgnoresBaseClass(test:TestCase) : Void {
    test.strictEqual(TestDeflatableNoVersionB.___deflatable_version(), 3);
    test.strictEqual(getVersionByReflection(TestDeflatableNoVersionB), 3);
  }

  @test static public function test_deflatableVersionForSpecifiedVersion(test:TestCase) : Void {
    test.strictEqual(TestDeflatableVersionA.___deflatable_version(), 1);
    test.strictEqual(getVersionByReflection(TestDeflatableVersionA), 1);
  }

  @test static public function test_deflatableVersionForMixedVersionIsSingleInteger(test:TestCase) : Void {
    test.strictEqual(TestDeflatableMixedVersionC.___deflatable_version(), 2);
    test.strictEqual(getVersionByReflection(TestDeflatableMixedVersionC), 2);
  }
}

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

package serialization.internal;

import serialization.internal.TypeUtils;

/**
 *  Faster setProperty API using for precached field name hashes (in C#)
 *  Usage: call/store hash() for property name
 *  Call setProperty using both the field name and field hash.
 */
class FastReflect
{
  static var fieldIds:Array<Int> = [];
  static var fields:Array<String> = [];

  /** Copied from Haxe std/cs/internal/FieldLookup.hx */
  private static inline function doHash(s:String):Int {
    var acc = 0; //alloc_int
    for (i in 0...s.length)
    {
      acc = (( 223 * (acc >> 1) + s.charCodeAt(i) ) << 1);
    }

    return acc >>> 1; //always positive
  }

  /** Copied from Haxe std/cs/internal/FieldLookup.hx */
  public static function hash(s:String):Int {
    if (s == null) return 0;

    var key = doHash(s);

    //start of binary search algorithm
    var ids = fieldIds;
    var min = 0;
    var max = ids.length;

    while (min < max)
    {
      var mid = Std.int(min + (max - min) / 2); //overflow safe
      var imid = ids[mid];
      if (key < imid)
      {
        max = mid;
      } else if (key > imid) {
        min = mid + 1;
      } else {
        var field = fields[mid];
        if (field != s)
          return ~key; //special case
        return key;
      }
    }
    //if not found, min holds the value where we should insert the key
    ids.insert(min, key);
    fields.insert(min, s);
    return key;
  }

  #if cs
    #if debug
    @:functionCode('
      try {
        if (o is haxe.lang.IHxObject)
          ((haxe.lang.IHxObject) o).__hx_setField(field, hash, value, true);
        else if (haxe.lang.Runtime.slowHasField(o, "set_" + field))
          haxe.lang.Runtime.slowCallField(o, "set_" + field, new Array<object>(new object[]{value}));
        else
          haxe.lang.Runtime.slowSetField(o, field, value);
      } catch ( System.Exception e ) {
        UnityEngine.Debug.LogError("Failed to set property " + field + " on " + o.ToString() + " to value " + value.ToString() + ": " + e.ToString());
        throw e;
      }
    ')
    #else
    @:functionCode('
      if (o is haxe.lang.IHxObject)
        ((haxe.lang.IHxObject) o).__hx_setField(field, hash, value, true);
      else if (haxe.lang.Runtime.slowHasField(o, "set_" + field))
        haxe.lang.Runtime.slowCallField(o, "set_" + field, new Array<object>(new object[]{value}));
      else
        haxe.lang.Runtime.slowSetField(o, field, value);
    ')
    #end
  #end
  public #if (!cs) inline #end static function setProperty(o:Dynamic, field:String, hash:Int, value:Dynamic) : Void {
    #if debug
    try {
    #end
      Reflect.setProperty(o, field, value);
    #if debug
    } catch (e:Dynamic) {
      utils.Assert.fail('Failed to set property $field on $o to $value: $e');
    }
    #end
  }

  #if cs
  static var s_registeredClasses = new Map<TypeKey, Bool>();
  #end

  /** Faster version of Type.createEmptyInstance that caches whether class is a Haxe-generated class. */
  public inline static function createEmptyInstance( cl : Class<Dynamic> ) : Dynamic {
    #if cs
      var classKey = TypeUtils.keyForClass(cl);
      var isHX = s_registeredClasses.exists(classKey);
      if ( !isHX && untyped __cs__("cl.GetInterface(\"IHxObject\") != null") ) {
        s_registeredClasses.set(classKey, true);
        isHX = true;
      }

      return isHX ?
        untyped __cs__("
          cl.InvokeMember(\"__hx_createEmpty\",
            System.Reflection.BindingFlags.Static|
            System.Reflection.BindingFlags.Public|
            System.Reflection.BindingFlags.InvokeMethod|
            System.Reflection.BindingFlags.DeclaredOnly,
            null,
            null,
            new object[]{}
          )"
        ) : Type.createInstance(cl, []);
    #else
      return Type.createEmptyInstance(cl);
    #end
  }
}

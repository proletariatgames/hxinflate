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

import haxe.ds.StringMap;
import serialization.internal.TypeUtils;
import serialization.internal.RadixTree;
import serialization.stream.StringInflateStream;
import serialization.Inflater;

typedef DeflaterOptions = {
  ?purpose : String,
  ?typeDeflater : Deflater,
  ?stats : haxe.ds.StringMap<Int>,
  ?useEnumIndex : Bool,
  ?useEnumVersioning : Bool,
  ?useCache : Bool,
  ?skipHeader : Bool,
  ?compressStrings : Bool,
};


class DeflatedType {
  public var index : Int;
  public function new() {
    this.index = -1;
  }
}

class DeflatedClass extends DeflatedType {
  public var name : String;
  public var baseClassIndex : Int;
  public var custom : Bool;
  public var version : Int;
  public var startField : Int;
  public var numFields : Int;
  public var potentiallyStale : Bool;

  public function new() {
    super();
    this.name = null;
    this.baseClassIndex = -1;
    this.custom = false;
    this.version = -1;
    this.startField = 0;
    this.numFields = 0;
    this.potentiallyStale = false;
  }
}

class DeflatedEnumValue extends DeflatedType {
  public var construct : String;
  public var enumIndex : Int;
  public var typeIndex : Int;
  public var numParams : Int;

  public function new() {
    super();
    this.construct = null;
    this.enumIndex = -1;
    this.typeIndex = -1;
    this.numParams = 0;
  }
}

class DeflatedEnum extends DeflatedType {
  public var name : String;
  public var version : Int;
  public var useIndex : Bool;

  public function new() {
    super();
    this.name = null;
    this.version = -1;
    this.useIndex = false;
  }
}

/* Our Character codes
  "Z" - Deflater Version (first character)
  "V" - Final Type Info
  "W" - Base Type Info
  "T" - Index to Type Info in the cache
  "|" - Enum Type Info
  "=" - Enum Value Type Info
  "_" - Index to Enum Value Type Info in the cache
  "Y" - Raw String
  "R" - Our Raw String ref
  "S" - no field serialized (Skip)
  "N" - EnumValueMap
*/

  /* prefixes :
    a : array
    b : hash
    c : class
    C : custom
    d : Float
    e : reserved (float exp js)
    E : reserved (float exp cs)
    f : false
    g : object end
    h : array/list/hash end
    i : Int
    j : enum (by index)
    k : NaN
    l : list
    m : -Inf
    M : haxe.ds.ObjectMap
    n : null
    o : object
    p : +Inf
    q : haxe.ds.IntMap
    r : reference
    s : bytes (base64)
    t : true
    u : array nulls
    v : date
    w : enum
    x : exception
    y : urlencoded string
    z : zero
  */

// FIXME - need automagic Entity & Component serialization

class Deflater {

  /* Deflater Version history
  0 - Initial
  1 - Added serialized VERSION with "ZVER" character code,
      Serialize each class instance's full type and version hierarchy
  2 - Add deflater "purpose" string to the stream header
  3 - Change Skip code from E to S (fixes overload with float exp)
  */
  public static inline var VERSION_CODE = "ZVER";
  public static inline var VERSION : Int = 3;

  var buf : StringBuf;
  var cache : Array<Dynamic>;
  var shash : StringMap<Int>;
  var scount : Int;
  var rtree : RadixTree;

  static var BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%:";
  #if neko
  static var base_encode = neko.Lib.load("std","base_encode",2);
  #end

  public var options : DeflaterOptions;

  /**
    The individual cache setting for [this] Deflater instance.

    See USE_CACHE for a complete description.
  **/
  public var useCache(default, null) : Bool;

  /**
    The individual enum index setting for [this] Deflater instance.
  **/
  public var useEnumIndex(default, null) : Bool;

  var thash : StringMap<Array<DeflatedType>>;
  var tcount : Int;
  var farray : Array<String>;

  /**
    Creates a new Deflater instance.

    Subsequent calls to [this].serialize() will append values to the
    internal buffer of this String. Once complete, the contents can be
    retrieved through a call to [this].toString() .

    Each Deflater instance maintains its own cache if [this].useCache is
    true.
  **/
  public function new(?opt:DeflaterOptions) {
    buf = new StringBuf();
    cache = new Array();
    useCache = opt != null ? opt.useCache : false;
    useEnumIndex = opt != null ? opt.useEnumIndex : false;
    shash = new StringMap();
    scount = 0;
    rtree = new RadixTree();

    thash = new StringMap();
    tcount = 0;
    farray = [];

    options = {};
    options.purpose = (opt != null && opt.purpose != null) ? opt.purpose : null;
    options.typeDeflater = opt != null ? opt.typeDeflater : null;
    options.stats = opt != null ? opt.stats : null;
    options.compressStrings = (opt != null && opt.compressStrings != null) ? opt.compressStrings : false;
    options.useEnumVersioning = opt != null ? opt.useEnumVersioning : true;

    // Write our version at the top of the buffer
    if (opt == null || !opt.skipHeader) {
      buf.add(VERSION_CODE);
      buf.add(VERSION);
    }

    // Write the "purpose" string in our deflater options
    serialize(options.purpose);
  }

  function serializeString( s : String ) {
    // mini optimizations to improve codegen for JS
    inline function addInt(buf:StringBuf, x:Int) {
      #if js
        untyped buf.b += x;
      #else
        buf.add(x);
      #end
    }
    inline function addStr(buf:StringBuf, x:String) {
      #if js
        untyped buf.b += x;
      #else
        buf.add(x);
      #end
    }

    var td = options.typeDeflater;
    var buf = this.buf;
    if (td != null && td.options.compressStrings) {
      var id = td.rtree.serialize(s, td.buf, false);
      buf.add("~");
      addInt(buf, id);
    } else if (td == null && options.compressStrings) {
      rtree.serialize(s, buf, true);
    } else if (td != null) {
      var x = td.shash.get(s);
      if( x != null ) {
        buf.add("R");
        addInt(buf, x);
        return;
      }
      td.shash.set(s,td.scount);
      buf.add("R");
      addInt(buf, td.scount);
      td.scount++;

      td.buf.add("Y");
      addInt(td.buf, s.length);
      td.buf.add(":");
      addStr(td.buf, s);
    } else {
      var x = shash.get(s);
      if ( x != null ) {
        buf.add("R");
        addInt(buf, x);
      } else {
        shash.set(s,scount++);
        buf.add("Y"); // denotes raw (not url-encoded) string
        addInt(buf,s.length);
        buf.add(":");
        addStr(buf, s);
      }
    }
  }

  public static function inflateTypeInfo(buf:String) : Deflater {
    if (buf != null) {
      var inflater = Inflater.inflateTypeInfo(new StringInflateStream(buf));
      return getTypeInfoFromInflater(inflater);
    } else {
      return new Deflater();
    }
  }
  
  public static function getTypeInfoFromInflater(inflater:Inflater) {
    var deflater = new Deflater();
    var i_scache = inflater.scache;
    for (i in 0...i_scache.length) {
      deflater.serializeString(i_scache[i]);
    }
    if (deflater.scount != i_scache.length) {
      throw 'bad length';
    }
    for (i in 0...inflater.tcache.length) {
      var type = inflater.tcache[i];
      if (Std.is(type, serialization.InflatedEnum)) {
        var ctype:InflatedEnum = cast type;
        var info = new DeflatedEnum();
        info.name = ctype.name;
        info.index = deflater.tcount++;
        info.version = ctype.serialized_version;
        info.useIndex = ctype.useIndex;

        var mungedName = mungeClassName(ctype.name, ctype.serialized_version);
        if (!deflater.thash.exists(mungedName)) {
          deflater.thash.set(mungedName, []);
        }
        deflater.thash.get(mungedName).push(info);
        writeEnumInfo(deflater, info);
      }
      else if (Std.is(type, InflatedEnumValue)) {
        var ctype:InflatedEnumValue = cast type;
        var enumType = ctype.enumType;
        var info = new DeflatedEnumValue();
        info.construct = ctype.construct;
        info.index = deflater.tcount++;
        info.numParams = ctype.numParams;
        info.enumIndex = ctype.enumIndex;
        info.typeIndex = enumType.index;

        var mungedName = mungeClassName(enumType.name, enumType.serialized_version) + '::${ctype.construct}';
        if (!deflater.thash.exists(mungedName)) {
          deflater.thash.set(mungedName, []);
        }
        deflater.thash.get(mungedName).push(info);
        writeEnumValueInfo(deflater, info);
      }
      else {
        var ctype:InflatedClass = cast type;
        var info = new DeflatedClass();
        info.name = ctype.name;
        info.index = deflater.tcount++;
        info.baseClassIndex = ctype.baseClassIndex;
        info.custom = ctype.custom;
        info.version = ctype.serialized_version;
        info.startField = deflater.farray.length;
        info.numFields = ctype.numFields;
        info.potentiallyStale = true;

        var mungedName = mungeClassName(ctype.name, ctype.serialized_version);
        if (!deflater.thash.exists(mungedName)) {
          deflater.thash.set(mungedName, []);
        }
        deflater.thash.get(mungedName).push(info);

        deflater.buf.add("V");
        writeClassInfo(deflater, info, inflater.fcache.slice(ctype.startField, ctype.startField+ctype.numFields));
      }
    }
    if (deflater.tcount != inflater.tcache.length) {
      throw 'bad length';
    }
    
    return deflater;
  }

  /**
    Serializes `v`.

    We have special handling for versioned objects, ModelEntity and ModelComponents

    The values of [this].useCache and [this].useEnumIndex may affect
    serialization output.
  **/
  public function serialize( v : Dynamic ) {
    switch( Type.typeof(v) ) {
    case TClass(c):
      serializeClassInstance(v, c);
    case TNull:
      buf.add("n");
    case TInt:
      serializeInt(v);
    case TFloat:
      serializeFloat(v);
    case TBool:
      serializeBool(v);
    case TObject:
      serializeObject(v);
    case TEnum(e):
      if (options.useEnumVersioning) {
        var valueInfo = deflateEnum(v, e);
        deflateEnumValue(v, valueInfo);
      }
      else {
        serializeEnum(v, e);
      }
    case TFunction:
      throw "Cannot serialize function";
    default:
      #if neko
      if( untyped (__i32__kind != null && __dollar__iskind(v,__i32__kind)) ) {
        buf.add("i");
        buf.add(v);
        return;
      }
      #end
      throw "Cannot serialize "+Std.string(v);
    }
  }

  function serializeFields(v) {
    for( f in Reflect.fields(v) ) {
      serializeString(f);
      serialize(Reflect.field(v,f));
    }
    buf.add("g");
  }

  function serializeClassInstance(v:Dynamic, c:Class<Dynamic>) : Void {
    if( #if neko untyped c.__is_String #else c == String #end ) {
      serializeString(v);
      return;
    }
    if( useCache && serializeRef(v) )
      return;
    cache.pop();
    switch( #if (neko || cs) Type.getClassName(c) #else c #end ) {
    case #if (neko || cs) "Array" #else cast Array #end:
      serializeArray(v);
    case #if (neko || cs) "List" #else cast List #end:
      serializeList(v);
    case #if (neko || cs) "Date" #else cast Date #end:
      serializeDate(v);
    case #if (neko || cs) "haxe.ds.StringMap" #else cast haxe.ds.StringMap #end:
      serializeStringMap(v);
    case #if (neko || cs) "haxe.ds.IntMap" #else cast haxe.ds.IntMap #end:
      serializeIntMap(v);
    case #if (neko || cs) "haxe.ds.ObjectMap" #else cast haxe.ds.ObjectMap #end:
      serializeObjectMap(v);
    case #if (neko || cs) "haxe.io.Bytes" #else cast haxe.io.Bytes #end:
      serializeBytes(v);
    case #if (neko || cs) "haxe.ds.EnumValueMap" #else cast haxe.ds.EnumValueMap #end:
      serializeEnumValueMap(v);
    default:
      // do our versioned serialization
      // first find / create our class info
      var info = deflateClass(v, c);
      deflateInstance(v, info);
    }
  }

  inline function serializeArray(v : Dynamic) : Void {
    var ucount = 0;
    buf.add("a");
    #if flash9
    var v : Array<Dynamic> = v;
    #end
    var l = #if (neko || flash9 || php || cs || java) v.length #elseif cpp v.__length() #else v[untyped "length"] #end;
    for( i in 0...l ) {
      if( v[i] == null )
        ucount++;
      else {
        if( ucount > 0 ) {
          if( ucount == 1 )
            buf.add("n");
          else {
            buf.add("u");
            buf.add(ucount);
          }
          ucount = 0;
        }
        serialize(v[i]);
      }
    }
    if( ucount > 0 ) {
      if( ucount == 1 )
        buf.add("n");
      else {
        buf.add("u");
        buf.add(ucount);
      }
    }
    buf.add("h");
  }

  inline function serializeList(v : Dynamic) : Void {
    buf.add("l");
    var v : List<Dynamic> = v;
    for( i in v )
      serialize(i);
    buf.add("h");
  }

  inline function serializeDate(v : Dynamic) : Void {
    var d : Date = v;
    buf.add("v");
    buf.add(d.toString());
  }

  inline function serializeStringMap(v : Dynamic) : Void {
    buf.add("b");
    var v : haxe.ds.StringMap<Dynamic> = v;
    for( k in v.keys() ) {
      serializeString(k);
      serialize(v.get(k));
    }
    buf.add("h");
  }

  inline function serializeIntMap(v : Dynamic) : Void {
    buf.add("q");
    var v : haxe.ds.IntMap<Dynamic> = v;
    for( k in v.keys() ) {
      buf.add(":");
      buf.add(k);
      serialize(v.get(k));
    }
    buf.add("h");
  }

  inline function serializeObjectMap(v : Dynamic) : Void {
    buf.add("M");
    var v : haxe.ds.ObjectMap<Dynamic,Dynamic> = v;
    for ( k in v.keys() ) {
      #if (js || flash8 || neko)
      var id = Reflect.field(k, "__id__");
      Reflect.deleteField(k, "__id__");
      serialize(k);
      Reflect.setField(k, "__id__", id);
      #else
      serialize(k);
      #end
      serialize(v.get(k));
    }
    buf.add("h");
  }

  inline function serializeBytes(v : Dynamic) : Void {
    var v : haxe.io.Bytes = v;
    #if neko
    var chars = new String(base_encode(v.getData(),untyped BASE64.__s));
    #else
    var i = 0;
    var max = v.length - 2;
    var charsBuf = new StringBuf();
    var b64 = BASE64;
    while( i < max ) {
      var b1 = v.get(i++);
      var b2 = v.get(i++);
      var b3 = v.get(i++);

      charsBuf.add(b64.charAt(b1 >> 2));
      charsBuf.add(b64.charAt(((b1 << 4) | (b2 >> 4)) & 63));
      charsBuf.add(b64.charAt(((b2 << 2) | (b3 >> 6)) & 63));
      charsBuf.add(b64.charAt(b3 & 63));
    }
    if( i == max ) {
      var b1 = v.get(i++);
      var b2 = v.get(i++);
      charsBuf.add(b64.charAt(b1 >> 2));
      charsBuf.add(b64.charAt(((b1 << 4) | (b2 >> 4)) & 63));
      charsBuf.add(b64.charAt((b2 << 2) & 63));
    } else if( i == max + 1 ) {
      var b1 = v.get(i++);
      charsBuf.add(b64.charAt(b1 >> 2));
      charsBuf.add(b64.charAt((b1 << 4) & 63));
    }
    var chars = charsBuf.toString();
    #end
    buf.add("s");
    buf.add(chars.length);
    buf.add(":");
    buf.add(chars);
  }

  inline function serializeEnumValueMap(v : Dynamic) : Void {
    buf.add("N");
    var v : haxe.ds.EnumValueMap<Dynamic,Dynamic> = v;
    for ( k in v.keys() ) {
      serialize(k);
      serialize(v.get(k));
    }
    buf.add("h");
  }

  function serializeRef(v) {
    #if js
    var vt = untyped __js__("typeof")(v);
    #end
    for( i in 0...cache.length ) {
      #if js
      var ci = cache[i];
      if( untyped __js__("typeof")(ci) == vt && ci == v ) {
      #else
      if( cache[i] == v ) {
      #end
        buf.add("r");
        buf.add(i);
        return true;
      }
    }
    cache.push(v);
    return false;
  }

  inline function serializeInt(v : Dynamic) : Void {
    if( v == 0 ) {
      buf.add("z");
    } else {
      buf.add("i");
      buf.add(v);
    }
  }

  inline function serializeFloat(v : Dynamic) : Void {
    if( Math.isNaN(v) )
      buf.add("k");
    else if( !Math.isFinite(v) )
      buf.add(if( v < 0 ) "m" else "p");
    else {
      buf.add("d");
      buf.add(v);
    }
  }

  inline function serializeBool(v : Dynamic) : Void {
    buf.add(if( v ) "t" else "f");
  }

  function serializeObject(v : Dynamic) : Void {
    if( useCache && serializeRef(v) )
      return;
    buf.add("o");
    serializeFields(v);
  }

  inline function serializeEnum(v : Dynamic, e : Enum<Dynamic>) : Void {
    if (!useCache || !serializeRef(v)) {
      cache.pop();
      buf.add(useEnumIndex?"j":"w");
      serializeString(Type.getEnumName(e));
      #if neko
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(v.index);
      } else
        serializeString(new String(v.tag));
      buf.add(":");
      if( v.args == null )
        buf.add(0);
      else {
        var l : Int = untyped __dollar__asize(v.args);
        buf.add(l);
        for( i in 0...l )
          serialize(v.args[i]);
      }
      #elseif flash9
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(v.index);
      } else
        serializeString(v.tag);
      buf.add(":");
      var pl : Array<Dynamic> = v.params;
      if( pl == null )
        buf.add(0);
      else {
        buf.add(pl.length);
        for( p in pl )
          serialize(p);
      }
      #elseif cpp
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(v.__Index());
      } else
        serializeString(v.__Tag());
      buf.add(":");
      var pl : Array<Dynamic> = v.__EnumParams();
      if( pl == null )
        buf.add(0);
      else {
        buf.add(pl.length);
        for( p in pl )
          serialize(p);
      }
      #elseif php
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(v.index);
      } else
        serializeString(v.tag);
      buf.add(":");
      var l : Int = untyped __call__("count", v.params);
      if( l == 0 || v.params == null)
        buf.add(0);
      else {
        buf.add(l);
        for( i in 0...l )
          serialize(untyped __field__(v, __php__("params"), i));
      }
      #elseif (java || cs)
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(Type.enumIndex(v));
      } else
        serializeString(Type.enumConstructor(v));
      buf.add(":");
      var arr:Array<Dynamic> = Type.enumParameters(v);
      if (arr != null)
      {
        buf.add(arr.length);
        for (v in arr)
          serialize(v);
      } else {
        buf.add("0");
      }

      #else
      if( useEnumIndex ) {
        buf.add(":");
        buf.add(v[1]);
      } else
        serializeString(v[0]);
      buf.add(":");
      var l = v[untyped "length"];
      buf.add(l - 2);
      for( i in 2...l )
        serialize(v[i]);
      #end
      cache.push(v);
    }
  }

  /**
    Return the String representation of [this] Deflater.

    The exact format specification can be found here:
    http://haxe.org/manual/serialization/format
  **/
  public function toString() {
    return buf.toString();
  }

  /**
    Serializes `v` and returns the String representation.

    This is a convenience function for creating a new instance of
    Deflater, serialize `v` into it and obtain the result through a call
    to toString().
  **/
  public static function run( v : Dynamic , ?options : DeflaterOptions ) {
    var s = new Deflater(options);
    s.serialize(v);
    return s.toString();
  }

  inline static function hasCustom(cls : Class<Dynamic>) : Bool {
    return Lambda.has(Type.getInstanceFields(cls), "hxSerialize");
  }

  #if !flash9 inline #end static function callPre(value : Dynamic) {
    if( #if flash9 try value.preSerialize != null catch( e : Dynamic ) false #elseif (cs || java) Reflect.hasField(value, "preSerialize") #else value.preSerialize != null #end  ) {
      return true;
    }
    else
      return false;
  }

  #if !flash9 inline #end static function callPost(value : Dynamic) {
    if( #if flash9 try value.postSerialize != null catch( e : Dynamic ) false #elseif (cs || java) Reflect.hasField(value, "postSerialize") #else value.postSerialize != null #end  ) {
      return true;
    }
    else
      return false;
  }

  // Serialize type info for this class (and any base class types that haven't yet been serialized)
  public function deflateClass(value : Dynamic, cls:Class<Dynamic>) : DeflatedClass {
    return deflateClassImpl(value, cls, true);
  }

  inline static function mungeClassName(className:String, version:Int) : String {
    return '$className##$version';
  }

  function typeDiffersFromDeflatedClass(tdeflater:Deflater, cls:Class<Dynamic>, value:Dynamic, classVersion:Int, purpose:String, deflated:DeflatedClass) : Bool {
    // did custom change?
    var freshHasCustom = hasCustom(cls);
    if (deflated.custom != freshHasCustom) {
      throw '${Type.getClassName(cls)} hasCustom changed, but no version bump?!';
    }

    if( !freshHasCustom ) {
      var fields = TypeUtils.getSerializableFields(cls, value, purpose);
      if (fields.length != deflated.numFields) {
        if (fields.length < deflated.numFields) {
          throw ('${Type.getClassName(cls)} has less fields than previously deflated version:\n' +
            'Old version: ${tdeflater.farray.slice(deflated.startField, deflated.startField+deflated.numFields)}\n' +
            'New version: $fields');
        }
        return true;
      }

      var fstart = deflated.startField;
      for (i in 0...fields.length) {
        var fname = tdeflater.farray[fstart+i];
        if (fields[i] != fname) {
          return true;
        }
      }
    }

    var superClass = Type.getSuperClass(cls);
    var freshBaseClassIndex = -1;
    if (superClass != null) {
      var superClassInfo = deflateClassImpl(value, superClass, false);
      freshBaseClassIndex = superClassInfo.index;
    }

    if (deflated.baseClassIndex != freshBaseClassIndex) {
      throw '${Type.getClassName(cls)} changed base class, but no version bump?!';
    }

    return false;
  }

  public function deflateClassImpl(value : Dynamic, cls:Class<Dynamic>, isLastType:Bool) : DeflatedClass {
    var tdeflater;
    if ( options.typeDeflater != null ) {
      // store type info seperately if requested.
      tdeflater = options.typeDeflater;
    } else {
      tdeflater = this;
    }

    var classVersion = 0;
    var di: Dynamic = Reflect.field(cls, "___deflatable_version");
    // If it's not currently a Deflatable, it has version 0
    if (di != null) {
      classVersion = Reflect.callMethod(cls, di, []);
    }

    var name = Type.getClassName(cls);

    var mungedName = mungeClassName(name, classVersion);
    var types = tdeflater.thash.get(mungedName);
    var existingClass:DeflatedClass = null;
    if ( types != null ) {
      // get the most recent typeInfo serialized for this class
      existingClass = cast types[types.length-1];
      // If it was created from a potentially stale type info, check if it is up-to-date
      if (existingClass.potentiallyStale) {
        if (!typeDiffersFromDeflatedClass(tdeflater, cls, value, classVersion, options.purpose, existingClass)) {
          existingClass.potentiallyStale = false;
        } else {
          // Something changed in the type, but the version wasn't bumped.
          // (This is allowed if the type added a field.)
          // This means we need to store a new type information entry.
          existingClass = null;
        }
      }
    }

    if (existingClass != null) {
      // Only write the index if we need it to identify this instance
      if (isLastType) {
        buf.add("T");
        buf.add(existingClass.index);
        buf.add(":");
      }
      return existingClass;
    }

    // Recursively deflate our class hierachy, starting with the base class
    var superClass = Type.getSuperClass(cls);
    var superClassInfo = null;
    if (superClass != null) {
      superClassInfo = deflateClassImpl(value, superClass, false);
    }

    var info = new DeflatedClass();
    info.index = tdeflater.tcount++;
    info.baseClassIndex = superClassInfo != null ? superClassInfo.index : -1;
    info.name = name;
    info.custom = hasCustom(cls);
    info.version = classVersion;
    info.startField = tdeflater.farray.length;
    info.numFields = 0;
    info.potentiallyStale = false;

    if (!(superClassInfo == null || info.custom == superClassInfo.custom)) {
      throw 'Cannot serialize ${info.name}, does not share serialization method with ${superClassInfo.name}';
    }

    var fields : Array<String> = null;
    if( !info.custom ) {
      fields = TypeUtils.getSerializableFields(cls, value, options.purpose);
      info.numFields = fields.length;
    }

    if (!tdeflater.thash.exists(mungedName)) {
      tdeflater.thash.set(mungedName, []);
    }
    tdeflater.thash.get(mungedName).push(info);

    if (isLastType) {
      tdeflater.buf.add("V");
    } else {
      tdeflater.buf.add("W");
    }

    writeClassInfo(tdeflater, info, fields);

    if ( options.typeDeflater != null && isLastType ) {
      buf.add("T");
      buf.add(info.index);
      buf.add(":");
    }

    return info;
  }

  static function writeClassInfo(target:Deflater, info:DeflatedClass, fields:Array<String>) : Void {
    target.serializeString(info.name);
    target.buf.add(":");
    target.serialize(info.baseClassIndex);
    target.buf.add(":");
    target.serialize(info.version);
    target.buf.add(":");
    target.serialize(info.custom);
    target.buf.add(":");
    if (!info.custom) {
      if (fields.length != info.numFields) {
        throw 'bad length';
      }
      target.farray = target.farray.concat(fields);
      target.buf.add(info.numFields);
      target.buf.add(":");
      for (fname in fields)
        target.serializeString(fname);
      target.buf.add(":");
    }
  }

  public function verifyFields(v: Dynamic, info : DeflatedClass) {
    if ( info.custom ) {
      return;
    }

    var farray = ( options.typeDeflater != null ) ? options.typeDeflater.farray : this.farray;
    var cls = Type.getClass(v);

    var fields = TypeUtils.getSerializableFields(cls, v, options.purpose);

    var same = false;
    if (fields.length == info.numFields) {
      same = true;
      for (i in 0...fields.length) {
        if (fields[i] != farray[info.startField+i]) {
          same = false;
        }
      }
    }

    if (!same) {
      trace(info.name);
      trace(fields);
      for (i in 0...info.numFields) {
        trace(farray[info.startField+i]);
      }
    }
  }

  public function deflateInstance(v : Dynamic, info : DeflatedClass) {
    var startPos = 0;
    if ( options.stats != null ) {
      startPos = buf.toString().length;
    }

    cache.push(v);

    if (callPre(v)) {
      v.preSerialize(this);
    }

    if (info.custom) {
      v.hxSerialize(this);
    }
    else {
      var farray = ( options.typeDeflater != null ) ? options.typeDeflater.farray : this.farray;
      var fidx = info.startField;
      for (x in 0...info.numFields) {
        var fname = farray[fidx + x];
        if (#if js Reflect.hasField(v, fname) #else true #end) {
          var fval = #if js untyped v[fname] #else Reflect.field(v,fname) #end;
          serialize(fval);
        } else {
          // No data to serialize for this field
          buf.add("S");
        }
      }
    }

    buf.add("g");

    if (callPost(v)) {
      v.postSerialize();
    }

    if ( options.stats != null ) {
      var endPos = buf.toString().length;
      var name = Type.getClassName(Type.getClass(v));
      if ( !options.stats.exists(name) ) {
        options.stats.set(name, 0);
      }
      options.stats.set(name, options.stats.get(name) + (endPos-startPos));
    }
  }

  function deflateEnum(value : Dynamic, enm:Enum<Dynamic>) : DeflatedEnumValue {
    var tdeflater = options.typeDeflater != null ? options.typeDeflater : this;

    var enumName = Type.getEnumName(enm);
    var enumVersion = 0;

    var upgradeClassName = '${enumName}_deflatable';
    var upgradeClass:Class<Dynamic> = Type.resolveClass(upgradeClassName);
    var di: Dynamic = upgradeClass == null ? null : Reflect.field(upgradeClass, "___deflatable_version");
    // If it's not currently a Deflatable, it has version 0
    if (di != null) {
      enumVersion = Reflect.callMethod(upgradeClass, di, []);
    }

    var constructor = Type.enumConstructor(value);
    var mungedEnumName = mungeClassName(enumName, enumVersion);
    var mungedValueName = '$mungedEnumName::$constructor';
    var types = tdeflater.thash.get(mungedValueName);
    var existingValueInfo:DeflatedEnumValue = types != null ? cast types[types.length-1] : null;
    if (existingValueInfo != null) {
      // Only write the index if we need it to identify this instance
      buf.add("_");
      buf.add(existingValueInfo.index);
      buf.add(":");
      return existingValueInfo;
    }

    // lookup the enum type info
    types = tdeflater.thash.get(mungedEnumName);
    var existingInfo:DeflatedEnum = types != null ? cast types[types.length-1] : null;
    if (existingInfo == null) {
      var info = existingInfo = new DeflatedEnum();
      info.index = tdeflater.tcount++;
      info.name = enumName;
      info.version = enumVersion;
      info.useIndex = this.useEnumIndex;

      if (!tdeflater.thash.exists(mungedEnumName)) {
        tdeflater.thash.set(mungedEnumName, []);
      }
      tdeflater.thash.get(mungedEnumName).push(info);

      writeEnumInfo(tdeflater, info);
    }

    var info = new DeflatedEnumValue();
    info.index = tdeflater.tcount++;
    info.typeIndex = existingInfo.index;
    info.construct = existingInfo.useIndex ? null : constructor;
    info.enumIndex = Type.enumIndex(value);
    info.numParams = TypeUtils.getEnumParameterCount(enm, value);

    if (!tdeflater.thash.exists(mungedValueName)) {
      tdeflater.thash.set(mungedValueName, []);
    }
    tdeflater.thash.get(mungedValueName).push(info);

    writeEnumValueInfo(tdeflater, info);

    if ( options.typeDeflater != null ) {
      buf.add("_");
      buf.add(info.index);
      buf.add(":");
    }
    return info;
  }

  static function writeEnumInfo(target:Deflater, info:DeflatedEnum) : Void {
    target.buf.add("|");
    target.serializeString(info.name);
    target.buf.add(":");
    target.buf.add(info.version);
    target.buf.add(":");
    target.serialize(info.useIndex);
    target.buf.add(":");
  }

  static function writeEnumValueInfo(target:Deflater, info:DeflatedEnumValue) : Void {
    target.buf.add("=");
    target.serialize(info.construct);
    target.buf.add(":");
    target.buf.add(info.typeIndex);
    target.buf.add(":");
    target.buf.add(info.enumIndex);
    target.buf.add(":");
    target.buf.add(info.numParams);
    target.buf.add(":");
  }

  public function deflateEnumValue(v : Dynamic, valueInfo : DeflatedEnumValue) {
    if (!useCache || !serializeRef(v)) {
      cache.pop();

      var params = Type.enumParameters(v);
      var numParams = params == null ? 0 : params.length;
      if (valueInfo == null || valueInfo.numParams != numParams) {
        throw 'bad length';
      }

      for (x in 0...numParams) {
        serialize(params[x]);
      }
      cache.push(v);
    }
  }
}

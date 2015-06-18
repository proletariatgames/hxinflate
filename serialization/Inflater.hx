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
import serialization.stream.IInflateStream;
import serialization.stream.StringInflateStream;
import serialization.internal.TypeUtils;
import serialization.internal.FastReflect;

using StringTools;

typedef InflaterOptions = {
  ?typeInflater : Inflater,
  ?skipHeader : Bool,
};

class InflatedClass {
  public var name : String;
  public var type : Class<Dynamic>;
  public var index : Int;
  public var baseClassIndex : Int;
  public var custom : Bool;
  public var serialized_version : Int;
  public var startField : Int;
  public var numFields : Int;
  public var classUpgrade : Dynamic;
  public var requiresUpgrade : Bool;
  public var hasPostUnserialize : Int; // -1 if not yet determined
  #if debug
  public var currentFields : Array<String>;
  #end

  public function new() {
    this.name = null;
    this.type = null;
    this.index = -1;
    this.baseClassIndex = -1;
    this.custom = false;
    this.serialized_version = -1;
    this.startField = 0;
    this.numFields = 0;
    this.classUpgrade = null;
    this.requiresUpgrade = false;
    this.hasPostUnserialize = -1;
  }
}

private class InflatedEnumValue {
  public var name : String;
  public var numParams : Int;

  public function new() {
    this.name = null;
    this.numParams = 0;
  }
}

private class InflatedEnum {
  public var name : String;
  public var type : Enum<Dynamic>;
  public var serialized_version : Int;
  public var upgradeFunc : Dynamic;
  public var upgradeClass : Class<Dynamic>;
  public var requiresUpgrade : Bool;
  public var values : Array<InflatedEnumValue>;

  public function new() {
    this.name = null;
    this.type = null;
    this.serialized_version = -1;
    this.upgradeFunc = null;
    this.upgradeClass = null;
    this.requiresUpgrade = false;
    this.values = [];
  }
}

@:allow(serialization.Deflater)
class Inflater {
  var deflaterVersion : Int;

  static var BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%:";
  #if neko
  static var base_decode = neko.Lib.load("std","base_decode",2);
  #end

  static var CODES = null;

  static function initCodes() {
    var codes =
      #if flash9
        new flash.utils.ByteArray();
      #else
        new Array();
      #end
    for( i in 0...BASE64.length )
      codes[fastCodeAt(BASE64,i)] = i;
    return codes;
  }

  var stream : IInflateStream;
  var length : Int;
  var cache : Array<Dynamic>;
  var scache : Array<String>;
  #if neko
  var upos : Int;
  #end

  var tcache : Array<Dynamic>;
  var fcache : Array<String>;
  var hcache : Array<Int>;
  var ecache : Map<String, InflatedEnum>;
  var skipCounter : Int;

  public var purpose(default, null) : String;
  public var entities : Array<Dynamic>;

  // The code for skipping would conflict with floats ("E").
  // If infalating version <= 2, then skipCode should be set back to "E".
  var skipCode : Int = "S".code;

  /**
    Creates a new Inflater instance with the specified input stream.

    This does not parse all of this stream immediately, but it reads in the stream's version.  The rest iss parsed
    only when calls to [this].unserialize are made.

    Each Inflater instance maintains its own cache.
    We have special handling for versioned objects
  **/
  public function new(stream:IInflateStream, ?opt:InflaterOptions) {
    this.stream = stream;
    length = stream.getLength();
    #if neko
    upos = 0;
    #end
    scache = new Array();
    cache = new Array();
    ecache = new Map();

    if ( opt != null && opt.typeInflater != null ) {
      tcache = opt.typeInflater.tcache;
      fcache = opt.typeInflater.fcache;
      hcache = opt.typeInflater.hcache;
      scache = opt.typeInflater.scache;
    } else {
      tcache = [];
      fcache = [];
      hcache = [];
    }
    entities = [];

    if (opt != null && opt.skipHeader) {
      this.deflaterVersion = Deflater.VERSION;
    } else {
      // Look up our version at the top of the buffer
      var prevPos = stream.getPos();
      var code = stream.readString(Deflater.VERSION_CODE.length);
      if (code == Deflater.VERSION_CODE) {
        this.deflaterVersion = readDigits();
      } else {
        this.stream.seekTo(prevPos);
        // Version 0 is from before we serialized our version
        this.deflaterVersion = 0;
      }
    }

    if (opt != null && opt.typeInflater != null && opt.typeInflater.deflaterVersion != this.deflaterVersion) {
      if (!((opt.typeInflater.deflaterVersion == 2 && this.deflaterVersion == 1) ||
            (opt.typeInflater.deflaterVersion == 3 && this.deflaterVersion == 1) ||
            (opt.typeInflater.deflaterVersion == 3 && this.deflaterVersion == 2))) {
        throw 'Type inflater version was ${opt.typeInflater.deflaterVersion}, but ours is $deflaterVersion';
      }
    }

    // Get our purpose string
    if (this.deflaterVersion >= 2) {
      this.purpose = unserialize();
    }

    // old streams used a different skip code
    if (this.deflaterVersion < 3) {
      this.skipCode = "E".code;
    }
  }

  public static inline function fastCodeAt(s:String, i:Int) : Int {
    #if cs
      return untyped s[i];
    #else
      return StringTools.fastCodeAt(s, i);
    #end
  }

  // Used by custom serialization to get the version of the class that's being inflated
  public function getClassVersion(cls:Class<Dynamic>, instanceClassIndex:Int) : Int {
    var classIndex = instanceClassIndex;
    while (true) {
      if (classIndex == -1) {
        break;
      }
      var inflatedClass = tcache[classIndex];
      if (inflatedClass.type == cls) {
        return inflatedClass.serialized_version;
      }
      classIndex = inflatedClass.baseClassIndex;
    }
    throw 'Cannot find class version for $cls in given index';
    return -1;
  }

  public static function inflateTypeInfo(stream:IInflateStream) : Inflater {
    var inflater = new Inflater(stream);
    var result = [];
    var len = stream.getLength();
    while ( inflater.stream.getPos() != len ) {
      switch (inflater.stream.readByte()) {
      case "V".code:
        inflater.inflateClassInfo(true);
      case "W".code:
        inflater.inflateClassInfo(false);
      // string cache
      case "Y".code:
        inflater.unserializeRawString();
      case "y".code:
        inflater.unserializeURLEncodedString();
      }
    }
    return inflater;
  }

  function inflateClassInfo(lastClassType:Bool) : InflatedClass {
    var info : InflatedClass = new InflatedClass();
    info.startField = fcache.length;
    info.name = unserialize();
    if( stream.readByte() != ":".code ) {
      throw "Invalid type format (cls)";
    }
    info.type = Type.resolveClass(info.name);
    if( info.type == null ) {
      // Handle private becoming public
      // (Haxe inserts a "_" in private classes)
      var parts = info.name.split(".");
      if (parts.length > 1) {
        var pi = parts.length-2;
        var pack = parts[pi];
        if (pack.startsWith("_")) {
          parts.splice(pi, 1);
          var newName = parts.join('.');
          info.type = Type.resolveClass(newName);
          if (info.type != null) {
            info.name = newName;
          }
        }
      }
    }

    // Base Class Index
    if (this.deflaterVersion >= 1) {
      info.baseClassIndex = unserialize();
      if ( stream.readByte() != ":".code ) {
        throw "Invalid type format (baseClassIndex)";
      }
    } else {
      // No baseClassIndex before v1
      info.baseClassIndex = -1;
    }

    // Version
    if (this.deflaterVersion >= 1) {
      info.serialized_version = unserialize();
    } else {
      // We used to serialize strings for versions, but we hadn't started using the version tag so it should be null
      var oldVersion:String = unserialize();
      if (oldVersion != null) {
        throw 'oldVersion != null';
      }
      info.serialized_version = 0;
    }
    if ( stream.readByte() != ":".code ) {
      throw "Invalid type format (version)";
    }


    info.custom = unserialize();
    if( stream.readByte() != ":".code ) {
      throw "Invalid type format (custom)";
    }

    if (!info.custom) {
      info.numFields = readDigits();
      if( stream.readByte() != ":".code ) {
        throw "Invalid type format (fields)";
      }
      for (f in 0...info.numFields) {
        var fieldName:String = unserialize();
        fcache.push(fieldName);
        hcache.push(FastReflect.hash(fieldName));
      }
      if( stream.readByte() != ":".code ) {
        throw "Invalid type format (fields end)";
      }
    }

    info.index = tcache.length;
    tcache.push(info);

    if (info.type != null) {
      // See if we need to upgrade this class
      var currentVersion = 0;
      var di: Dynamic = Reflect.field(info.type, "___deflatable_version");
      if (di != null) {
        currentVersion = Reflect.callMethod(info.type, di, []);
      }

      if (info.serialized_version != currentVersion) {
        // Find the upgrade function we need to call for this class
        var fnName = '_upgrade_version';
        info.classUpgrade = Reflect.field(info.type, fnName);
        if (info.classUpgrade == null && !info.custom) {
          throw 'Please implement ${fnName} for class ${info.name}, need to upgrade from version ${info.serialized_version}';
        }
      }

      // An instance needs an upgrade if this or any base class needs a class upgrade
      var hierarchyInfo = info;
      while (true) {
        if (hierarchyInfo.classUpgrade != null || hierarchyInfo.requiresUpgrade) {
          info.requiresUpgrade = true;
          break;
        }
        if (hierarchyInfo.baseClassIndex == -1) {
          break;
        }
        hierarchyInfo = tcache[hierarchyInfo.baseClassIndex];
      }

      // Populate the info with a cache of fields that belong to the current version of this class
      #if debug
      info.currentFields = TypeUtils.getSerializableFieldsByClass(info.type, purpose);
      #end
    } else {
      if (this.skipCounter == 0 && !RemovedTypes.names.exists(info.name)) {
        throw 'Class not found ${info.name}';
      }
    }

    if (lastClassType) {
      return info;
    } else {
      // There's another class type ahead of us that we need to inflate
      switch (stream.readByte()) {
      case "V".code:
        return inflateClassInfo(true);
      case "W".code:
        return inflateClassInfo(false);
      default:
        throw 'Invalid type format - missing version info for lastClassType';
        return null;
      }
    }
  }

  public function inflateClass() : InflatedClass {
    switch( stream.readByte() ) {
    default:
      throw "Invalid instance type";
      return null;
    case "T".code:
      var t = readDigits();
      if( t < 0 || t >= tcache.length )
        throw "Invalid type reference";
      if( stream.readByte() != ":".code )
        throw "Invalid type reference format";
      return tcache[t];
    case "V".code:
      return inflateClassInfo(true);
    case "W".code:
      return inflateClassInfo(false);
    }
  }

  public function skipInstanceOf(type:InflatedClass) : Void {
    if (type.custom) {
      if (type.type == null) {
        throw 'Cannot skip an instance of a type that no longer exists and had custom serialization: ${type.name}';
      }
      var o = Type.createEmptyInstance(type.type);
      o.hxUnserialize(this, type.index);
    } else {
      // unserialize each field and throw it away.
      this.skipCounter++;
      for (x in 0...type.numFields) {
        if (stream.peekByte() != this.skipCode) {
          unserialize();
        } else {
          // Just skip the S and move on
          stream.readByte();
        }
      }
      if( stream.readByte() != "g".code ) {
        throw 'Invalid class data for instance of ${type.name} at pos ${stream.getPos()-1} in buf $stream';
      }

      this.skipCounter--;
    }
  }

  static function callPost(value : Dynamic) {
    if( #if flash9 try value.postUnserialize != null catch( e : Dynamic ) false #elseif (cs || java) Reflect.hasField(value, "postUnserialize") #else value.postUnserialize != null #end  ) {
      return true;
    }
    else
      return false;
  }

  @:keep public inline function inflateInstance(o:Dynamic, info : InflatedClass) : Dynamic {
    cache.push(o);
    if (info.custom) {
      o.hxUnserialize(this, info.index);
    } else {
      // Only allocate a field map if we have to upgrade this instance
      var fieldMap = (info.requiresUpgrade ? new Map<String, Dynamic>() : null);

      for (x in 0...info.numFields) {
        var fname = fcache[info.startField + x];
        var fhash = hcache[info.startField + x];
        if (stream.peekByte() != this.skipCode) {
          var val = unserialize();

          if (info.requiresUpgrade) {
            if (fieldMap == null) {
              throw 'fieldMap == null';
            }
            // Set up our field map if we need to upgrade
            fieldMap.set(fname, val);
          } else {
            // No upgrade, just set the field directly
            #if debug
              if (!TypeUtils.hasSerializableField(o, fname, info.currentFields)) {
                throw "Cannot set unserialized field: " + fname + " for type: " + info.name;
              }
            #end
            FastReflect.setProperty(o, fname, fhash, val);
          }
        } else {
          // Just skip the S and move on
          stream.readByte();
        }
      }

      // Upgrade our field map and then set values on the instance
      if (info.requiresUpgrade) {
        if (fieldMap == null) {
          throw 'fieldMap == null';
        }
        // Call update on each class in the hierarchy
        upgradeFieldMap(o, fieldMap, info);

        for (fname in fieldMap.keys()) {
          #if debug
            if (!TypeUtils.hasSerializableField(o, fname, info.currentFields)) {
              throw "Cannot set upgraded field: " + fname + " for type: " + info.name;
            }
          #end
          Reflect.setProperty(o, fname, fieldMap[fname]);
        }
      }

    }

    if( stream.readByte() != "g".code ) {
      throw 'Invalid class data for instance of ${info.name} at pos ${stream.getPos()-1} in buf $stream';
    }

    if (info.hasPostUnserialize == -1) {
      info.hasPostUnserialize = callPost(o) ? 1 : 0;
    }
    if (info.hasPostUnserialize == 1) {
      o.postUnserialize();
    }

    return o;
  }

  function upgradeFieldMap(o:Dynamic, fieldMap:Map<String, Dynamic>, info:InflatedClass) : Void {
    // First upgrade the fields on any base classes
    if (info.baseClassIndex != -1) {
      upgradeFieldMap(o, fieldMap, tcache[info.baseClassIndex]);
    }
    if (info.classUpgrade != null) {
      Reflect.callMethod(info.type, info.classUpgrade, [o, info.serialized_version, fieldMap]);
    }
  }

  inline function unserializeInstance() : Dynamic {
    var info = inflateClass();
    if (info.type != null) {
      var o = FastReflect.createEmptyInstance(info.type);
      return inflateInstance(o, info);
    } else if (this.skipCounter > 0 || RemovedTypes.names.exists(info.name)) {
      skipInstanceOf(info);
      return null;
    } else {
      throw 'Missing required code for ${info.name}';
      return null;
    }
  }

  public function inflateEnum() : InflatedEnum {
    switch( stream.readByte() ) {
    default:
      throw "Invalid enum type";
      return null;
    case "-".code:
      var t = readDigits();
      if( t < 0 || t >= tcache.length )
        throw "Invalid enum type reference";
      if( stream.readByte() != ":".code )
        throw "Invalid enum type reference format";
      return tcache[t];
    case "_".code:
      return inflateEnumInfo();
    }
  }

  function setupInflatedEnum(name:String, serialized_version:Int) : InflatedEnum {
    var info = new InflatedEnum();
    info.name = name;
    info.serialized_version = serialized_version;
    info.type = Type.resolveEnum(name);

    if (info.type != null) {
      // See if we need to upgrade this class
      var currentVersion = 0;
      var upgradeClassName = '${info.name}_deflatable';
      var upgradeClass:Class<Dynamic> = Type.resolveClass(upgradeClassName);
      var di: Dynamic = upgradeClass == null ? null : Reflect.field(upgradeClass, "___deflatable_version");
      // If it's not currently a Deflatable, it has version 0
      if (di != null) {
        currentVersion = Reflect.callMethod(upgradeClass, di, []);
      }

      if (info.serialized_version != currentVersion) {
        // Find the upgrade function we need to call for this class
        var fnName = '_upgrade_enum';
        info.requiresUpgrade = true;
        info.upgradeClass = upgradeClass;
        info.upgradeFunc = upgradeClass == null ? null : Reflect.field(upgradeClass, fnName);
        if (info.upgradeFunc == null) {
          throw 'Please implement ${fnName} for class ${upgradeClassName}, need to upgrade from version ${info.serialized_version}';
        }
      }
    } else {
      if (this.skipCounter == 0 && !RemovedTypes.names.exists(info.name)) {
        throw 'Enum not found ${info.name}';
      }
    }

    return info;
  }

  function inflateEnumInfo() : InflatedEnum {
    var name = unserialize();
    if( stream.readByte() != ":".code ) {
      throw "Invalid type format (cls)";
    }
    var serialized_version = readDigits();
    if ( stream.readByte() != ":".code ) {
      throw "Invalid type format (version)";
    }

    var info = setupInflatedEnum(name, serialized_version);
    var numConstructors = readDigits();
    if( stream.readByte() != ":".code ) {
      throw "Invalid type format (numConstructors)";
    }
    for (f in 0...numConstructors) {
      var valueInfo : InflatedEnumValue = new InflatedEnumValue();
      valueInfo.name = unserialize();
      if( stream.readByte() != ":".code ) {
        throw "Invalid type format (constructor)";
      }
      valueInfo.numParams = readDigits();
      if( stream.readByte() != ":".code ) {
        throw "Invalid type format (numParams)";
      }
      info.values.push(valueInfo);
    }

    tcache.push(info);
    return info;
  }

  function skipEnumValue(info : InflatedEnum, valueInfo : InflatedEnumValue) : Void {
    // unserialize each parameter and throw it away.
    this.skipCounter++;

    var params = valueInfo.numParams == 0 ? null : [for (i in 0...valueInfo.numParams) unserialize()];

    this.skipCounter--;
  }

  @:keep inline function inflateEnumValue(info : InflatedEnum, valueInfo : InflatedEnumValue) : Dynamic {
    var params = valueInfo.numParams == 0 ? null : [for (i in 0...valueInfo.numParams) unserialize()];

    // Upgrade our param array before we construct the enum
    var data = {constructor: valueInfo.name, params: params};
    if (info.requiresUpgrade) {
      Reflect.callMethod(info.upgradeClass, info.upgradeFunc, [info.serialized_version, data]);
    }

    try {
      return Type.createEnum(info.type, data.constructor, data.params);
    }
    catch (e:Dynamic){
      throw 'Failed to create enum ${info.type}.${data.constructor}(${data.params}) : $e';
    }
  }

  inline function unserializeEnumValueCommon(info:InflatedEnum, valueInfo:InflatedEnumValue) : Dynamic {
    var e = null;
    if (info.type != null) {
      e = inflateEnumValue(info, valueInfo);
    } else if (this.skipCounter > 0 || RemovedTypes.names.exists(info.name)) {
      skipEnumValue(info, valueInfo);
    } else {
      throw 'Missing required code for ${info.name}';
    }
    cache.push(e);
    return e;
  }

  inline function unserializeEnumValue() : Dynamic {
    var info = inflateEnum();
    var idx = unserialize();
    return unserializeEnumValueCommon(info, info.values[idx]);
  }

  function unserializeOldEnumValue(useIndex:Bool) : Dynamic {
    var name = unserialize();
    var info = ecache[name];
    if (info == null) {
      ecache[name] = info = setupInflatedEnum(name, 0);
      var constructs = info.type == null ? [] : Type.getEnumConstructs(info.type);
      for (construct in constructs) {
        var valueInfo = new InflatedEnumValue();
        valueInfo.name = construct;
        valueInfo.numParams = 0;
        info.values.push(valueInfo);
      }
    }

    var valueInfo = null;
    if (useIndex) {
      if( stream.readByte() != ":".code ) {
        throw "Invalid type format (old enum index)";
      }
      var index = readDigits();
      valueInfo = info.values[index];
      if (valueInfo == null && info.type != null) {
        throw 'Unknown enum constructor $name@$index';
      }
    }
    else {
      var constructor = unserialize();
      for (entry in info.values) {
        if(entry.name == constructor) {
          valueInfo = entry;
          break;
        }
      }
      if (valueInfo == null) {
        valueInfo = new InflatedEnumValue();
        valueInfo.name = constructor;
      }
    }

    if( stream.readByte() != ":".code )
      throw "Invalid enum format";

    valueInfo.numParams = readDigits();
    return unserializeEnumValueCommon(info, valueInfo);
  }

  inline function unserializeEnumValueMap() : Dynamic {
    var h = new haxe.ds.EnumValueMap();
    cache.push(h);
    while( stream.peekByte() != "h".code ) {
      var s:Dynamic = unserialize();
      h.set(s,unserialize());
    }
    stream.readByte();
    return h;
  }

  inline function unserializeRawString() : Dynamic {
    var len = readDigits();
    if( stream.readByte() != ":".code || length - stream.getPos() < len )
      throw "Invalid string length";
    var s = stream.readString(len);
    scache.push(s);
    return s;
  }

  inline function unserializeURLEncodedString() : Dynamic {
    var len = readDigits();
    if( stream.readByte() != ":".code || length - stream.getPos() < len )
      throw "Invalid string length";
    var s = stream.readString(len);
    s = StringTools.urlDecode(s);
    scache.push(s);
    return s;
  }

  inline function unserializeRawStringReference() : Dynamic {
    var n = readDigits();
    if( n < 0 || n >= scache.length )
      throw "Invalid string reference";
    return scache[n];
  }

  inline function unserializeObject() : Dynamic {
    var o = {};
    cache.push(o);
    while( true ) {
      if( stream.eof() )
        throw "Invalid object";
      if( stream.peekByte() == "g".code )
        break;
      var k = unserialize();
      if( !Std.is(k,String) )
        throw "Invalid object key";
      var v = unserialize();
      Reflect.setField(o,k,v);
    }
    stream.readByte();
    return o;
  }

  inline function unserializeReference() : Dynamic {
    var n = readDigits();
    if( n < 0 || n >= cache.length )
      throw "Invalid reference";
    return cache[n];
  }

  inline function readDigits() {
    var k = 0;
    var s = false;
    var fpos = stream.getPos();
    while( !stream.eof() ) {
      var c = stream.peekByte();
      if( c == "-".code ) {
        if( stream.getPos() != fpos ) {
          break;
        }
        s = true;
        stream.readByte();
        continue;
      }
      if( c < "0".code || c > "9".code ) {
        break;
      }
      k = k * 10 + (c - "0".code);
      stream.readByte();
    }
    if( s )
      k *= -1;
    return k;
  }

  inline function unserializeFloat() : Dynamic {
    var p1 = stream.getPos();
    while( !stream.eof() ) {
      var c = stream.peekByte();
      // + - . , 0-9
      if( (c >= 43 && c < 58) || c == "e".code || c == "E".code ) {
        stream.readByte();
      } else {
        break;
      }
    }
    var pos = stream.getPos();
    stream.seekTo(p1);
    return Std.parseFloat(stream.readString(pos-p1));
  }

  inline function unserializeArray() : Dynamic {
    var a = new Array<Dynamic>();
    cache.push(a);
    while( true ) {
      var c = stream.peekByte();
      if( c == "h".code ) {
        stream.readByte();
        break;
      }
      if( c == "u".code ) {
        stream.readByte();
        var n = readDigits();
        a[a.length+n-1] = null;
      } else {
        a.push(unserialize());
      }
    }
    return a;
  }

  inline function unserializeList() : Dynamic {
    var l = new List();
    cache.push(l);
    while( stream.peekByte() != "h".code )
      l.add(unserialize());
    stream.readByte();
    return l;
  }

  inline function unserializeStringMap() : Dynamic {
    var h = new haxe.ds.StringMap();
    cache.push(h);
    while( stream.peekByte() != "h".code ) {
      var s = unserialize();
      h.set(s,unserialize());
    }
    stream.readByte();
    return h;
  }

  inline function unserializeIntMap() : Dynamic {
    var h = new haxe.ds.IntMap();
    cache.push(h);
    var c = stream.readByte();
    while( c == ":".code ) {
      var i = readDigits();
      h.set(i,unserialize());
      c = stream.readByte();
    }
    if( c != "h".code )
      throw "Invalid IntMap format";
    return h;
  }

  inline function unserializeObjectMap() : Dynamic {
    var h = new haxe.ds.ObjectMap();
    cache.push(h);
    while( stream.peekByte() != "h".code ) {
      var s = unserialize();
      h.set(s,unserialize());
    }
    stream.readByte();
    return h;
  }

  inline function unserializeDate() : Dynamic {
    var d = Date.fromString(stream.readString(19));
    cache.push(d);
    return d;
  }

  inline function unserializeBytes() : Dynamic {
    var len = readDigits();
    if( stream.readByte() != ":".code || length - stream.getPos() < len )
      throw "Invalid bytes length";
    var codes = CODES;
    if( codes == null ) {
      codes = initCodes();
      CODES = codes;
    }
    var i = 0;
    var rest = len & 3;
    var size = (len >> 2) * 3 + ((rest >= 2) ? rest - 1 : 0);
    var max = len - rest;
    var bytes = haxe.io.Bytes.alloc(size);
    var bpos = 0;
    while( i < max ) {
      var c1 = codes[stream.readByte()];
      var c2 = codes[stream.readByte()];
      bytes.set(bpos++,(c1 << 2) | (c2 >> 4));
      var c3 = codes[stream.readByte()];
      bytes.set(bpos++,(c2 << 4) | (c3 >> 2));
      var c4 = codes[stream.readByte()];
      bytes.set(bpos++,(c3 << 6) | c4);
      i += 4;
    }
    if( rest >= 2 ) {
      var c1 = codes[stream.readByte()];
      var c2 = codes[stream.readByte()];
      bytes.set(bpos++,(c1 << 2) | (c2 >> 4));
      if( rest == 3 ) {
        var c3 = codes[stream.readByte()];
        bytes.set(bpos++,(c2 << 4) | (c3 >> 2));
      }
    }
    cache.push(bytes);
    return bytes;
  }

  inline function unserializeCustom() : Dynamic {
    var name = unserialize();
    var cl = Type.resolveClass(name);
    if( cl == null )
      throw "Class not found " + name;
    var o : Dynamic = Type.createEmptyInstance(cl);
    cache.push(o);
    o.hxUnserialize(this);
    if( stream.readByte() != "g".code )
      throw "Invalid custom data";
    return o;
  }

  /**
    Unserializes the next part of [this] Inflater instance and returns
    the according value.

    This function may call Type.resolveClass to determine a
    Class from a String, and Type.resolveEnum to determine an
    Enum from a String.

    If [this] Inflater instance contains no more or invalid data, an
    exception is thrown.

    This operation may fail on structurally valid data if a type cannot be
    resolved or if a field cannot be set. This can happen when unserializing
    Strings that were serialized on a different haxe target, in which the
    serialization side has to make sure not to include platform-specific
    data.

    Classes are created from Type.createEmptyInstance, which means their
    constructors are not called.
  **/
  public function unserialize() : Dynamic {
    var byte = stream.readByte();
    switch( byte ) {
    case "T".code, "V".code, "W".code:
      // wind back so unserializeInstance can re-read the character code
      stream.seekTo(stream.getPos()-1);
      return unserializeInstance();
    case "-".code, "_".code:
      stream.seekTo(stream.getPos()-1);
      return unserializeEnumValue();
    case "Y".code: // raw string
      return unserializeRawString();
    case "N".code:
      return unserializeEnumValueMap();
    case "n".code:
      return null;
    case "t".code:
      return true;
    case "f".code:
      return false;
    case "z".code:
      return 0;
    case "i".code:
      return readDigits();
    case "d".code:
      return unserializeFloat();
    case "y".code:
      return unserializeURLEncodedString();
    case "k".code:
      return Math.NaN;
    case "m".code:
      return Math.NEGATIVE_INFINITY;
    case "p".code:
      return Math.POSITIVE_INFINITY;
    case "a".code:
      return unserializeArray();
    case "o".code:
      return unserializeObject();
    case "r".code:
      return unserializeReference();
    case "R".code:
      return unserializeRawStringReference();
    case "x".code:
      throw unserialize();
    case "w".code, "j".code:
      return unserializeOldEnumValue(byte == "j".code);
    case "l".code:
      return unserializeList();
    case "b".code:
      return unserializeStringMap();
    case "q".code:
      return unserializeIntMap();
    case "M".code:
      return unserializeObjectMap();
    case "v".code:
      return unserializeDate();
    case "s".code:
      return unserializeBytes();
    case "C".code:
      // Can we remove this? I don't think we've been using it
      return unserializeCustom();
    default:
    }
    throw ('Invalid char ${String.fromCharCode(byte)} at position ${stream.getPos()-1}');
  }

  /**
    Unserializes `v` and returns the according value.

    This is a convenience function for creating a new instance of
    Inflater with `v` as buffer and calling its unserialize() method
    once.
  **/
  public static function run( v : String, ?options:InflaterOptions ) : Dynamic {
    return new Inflater(new StringInflateStream(v), options).unserialize();
  }

  public function getStrings(set:Map<String, Bool>, filter:String->Bool) : Void {
    for (v in this.scache.filter(filter)) {
      set[v] = true;
    }
  }

  public function getTypes(set:Map<String, Bool>) : Void {
    for (type in this.tcache) {
      set[type.name] = true;
    }
  }

  public function getFields(set:Map<String, Bool>) : Void {
    for (f in this.fcache) {
      set[f] = true;
    }
  }
}

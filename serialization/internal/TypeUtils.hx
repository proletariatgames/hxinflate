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

import haxe.rtti.CType;
import haxe.xml.Fast;

#if cs
typedef TypeKey = cs.system.Type;
#else
typedef TypeKey = String;
#end

class TypeUtils
{
  @:meta(System.ThreadStatic)
  static var s_cachedRTTI : Map<TypeKey, TypeTree> = null;
  @:meta(System.ThreadStatic)
  static var s_instanceFieldCache : Map<String, Array<String>> = null;
  @:meta(System.ThreadStatic)
  static var s_staticFieldCache : Map<String, Array<String>> = null;

  /** Given an iterator, return an iterable. */
  public static inline function toIterable<T>(iterator:Iterator<T>) : Iterable<T> {
    return { iterator : function() { return iterator; } };
  }

  /** Return a string key for a class, suitable for Map */
  public static inline function keyForClass(cls:Class<Dynamic>) : TypeKey {
    #if cs
    return cs.Lib.toNativeType(cls);
    #else
    return Type.getClassName(cls);
    #end
  }

  /** Return true if the instance field on the specified class has the specified metadata */
  public static function fieldHasMeta(cls:Class<Dynamic>, field:String, attribute:String) : Bool {
    var meta = fieldMeta(cls, field);
    if ( meta != null ) {
      return Reflect.hasField(meta, attribute);
    }
    return false;
  }

  public static function fieldMeta(cls:Class<Dynamic>, field:String) : Dynamic {
    var meta = haxe.rtti.Meta.getFields(cls);
    if ( meta != null ) {
      if ( Reflect.hasField(meta, field) ) {
        return Reflect.field(meta, field);
      } else {
        var superCls = Type.getSuperClass(cls);
        if ( superCls != null ) {
          return fieldMeta(superCls, field);
        }
      }
    }
    return null;
  }

  public static function getSerializableFields(cls:Class<Dynamic>, instance:Dynamic, purpose:String) : Array<String> {
    if (s_instanceFieldCache == null) {
      s_instanceFieldCache = new Map();
    }

    var key = '${Type.getClassName(cls)}###$purpose';
    var result = s_instanceFieldCache[key];
    if (result == null) {
      var classFields = getSerializableFieldsByClass(cls, purpose);
      result = classFields.filter(function (fname) {
        return !Reflect.isFunction(Reflect.field(instance, fname));
      });
      // ensure that fields are always ordered the same
      result.sort(Reflect.compare);

      s_instanceFieldCache[key] = result;
    }
    return result;
  }

  public static function hasSerializableField(instance:Dynamic, field:String, classFields:Array<String>) : Bool {
    for (cachedField in classFields) {
      if (field == cachedField && !Reflect.isFunction(Reflect.field(instance, field))) {
        return true;
      }
    }
    return false;
  }

  // Returns the data we can get about serializable fields from just the type
  public static function getSerializableFieldsByClass(cls:Class<Dynamic>, purpose:String) : Array<String> {
    if (s_staticFieldCache == null) {
      s_staticFieldCache = new Map();
    }

    var key = '${Type.getClassName(cls)}###$purpose';
    var cached = s_staticFieldCache[key];
    if (cached != null) {
      return cached;
    }

    // Look for filters defined on this class and its base classes
    // Uses the pattern _CLASSNAME_shouldSerializeField
    var filters = [];
    var filterClass = cls;
    while (filterClass != null) {
      var fields = Type.getClassFields(filterClass);
      var className = Type.getClassName(filterClass).split(".").pop();
      var filterName = '_${className}_shouldSerializeField';
      if (Lambda.has(fields, filterName)) {
        filters.push({field:Reflect.field(filterClass, filterName), cls:filterClass});
      }
      filterClass = Type.getSuperClass(filterClass);
    }

    // Get the instance fields and filter out the stuff we don't serialize
    var rawFields = Type.getInstanceFields(cls);
    var filteredFields = [];
    for (fname in rawFields) {
      // Don't serialize any field that has a getter
      if (Lambda.has(rawFields, 'get_$fname')) {
        continue;
      }

      // filter by purpose
      // | purpose | @nostore(X) | serialized? |
      // ---------------------------------------
      // |  null   |  null       |     no      |
      // |  null   |  client     |     no      |
      // |  client |  null       |     no      |
      // |  client |  client     |    yes      |
      // |  client |  datastore  |     no      |
      //
      var meta = TypeUtils.fieldMeta(cls, fname);
      if (meta != null && Reflect.hasField(meta, "nostore")) {
        var nostore : Array<String> = meta.nostore;
        if (nostore == null || purpose == null) {
          continue;
        }

        if (purpose != null && !Lambda.has(nostore, purpose)) {
          continue;
        }
      }

      if (Lambda.exists(filters, function(filter) return !Reflect.callMethod(filter.cls, filter.field, [cls, fname]))) {
        continue;
      }

      filteredFields.push(fname);
    }

    s_staticFieldCache[key] = filteredFields;
    return filteredFields;
  }

  public static function getFieldTypeInfo(cls:Class<Dynamic>, fieldName:String) : haxe.rtti.CType {
    var classKey = keyForClass(cls);
    if ( s_cachedRTTI == null ) {
      s_cachedRTTI = new Map();
    }
    var infos = s_cachedRTTI[classKey];
    if ( infos == null ) {
      var rtti = Reflect.field(cls, "__rtti");
      if (rtti == null) throw 'Class ${Type.getClassName(cls)} does not have RTTI info';
      var x = Xml.parse(rtti).firstElement();
      if (x == null) throw 'Class ${Type.getClassName(cls)} does not have RTTI info';
      s_cachedRTTI[classKey] = infos = new haxe.rtti.XmlParser().processElement(x);
    }
    switch ( infos ) {
      case TClassdecl(classDef):
        for ( f in classDef.fields ) {
          if ( f.name == fieldName ) {
            return f.type;
          }
        }

        if ( classDef.superClass != null ) {
          var superClass = Type.resolveClass(classDef.superClass.path);
          if (superClass == null) {
            throw 'expected super class';
          }
          return getFieldTypeInfo(superClass, fieldName);
        } else {
          return null;
        }

    default:
      throw "Unexpected: " + infos;
    }

    return null;
  }

  public static function getEnumParameterCount(enm:Enum<Dynamic>, constructor:String) : Int {
    #if neko
    #elseif flash9
    #elseif cpp
    #elseif php
    #elseif (java || cs)
    #elseif js
      var f = Reflect.field(enm,constructor);
      if( f == null ) throw 'No such constructor $enm.$constructor';
      if( Reflect.isFunction(f) ) {
        return f.length;
      }
      return 0;
    #else
    #end
    return 0;
  }
}

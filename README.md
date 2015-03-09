Haxe Serialization Library
================

Library for supporting serialization of Haxe objects, for persisting to disk or other data stores. This is a fork of the [Haxe Standard Library's Serializer/Unserializer](http://haxe.org/manual/std-serialization.html), and is able to deserialize objects originally serialized with Serializer.

Features
===============

* **Type Versioning**: Allows classes to be modified, with custom upgrade functions for old serialized data.
* **Streams**: Deserialize objects directly from disk or any other input source.
* **Customization**: Control which properties on an object get serialized. 
* **Optimized Data Size**: Type information is only stored once per type, and can optionally be stored externally.
* **Fast Runtime**: Optimized performance (particularly for C#).

Usage
===============

Serializing An Object
-------

<pre>
    var def = new Deflater();
    defl.serialize(myObject);
    var serializedObject:String = defl.toString();
</pre>

Deserializing An Object
-------

<pre>
    var stm = new StringInflateStream(serializedObject);
    var inf = new Inflater(stm);
    var myObject:MyObjectType = inf.unserialize();
</pre>

Streams
==============

Inflater supports an abstract input stream. Streams can be used in order to avoid loading large serialized objects into
memory, by instead instantiating them directly from disk or network input. Two implementations are provided:

* `StringInflateStream` creates a stream from a String.
* `FileInflateStream` creates a stream from a file, using the Haxe File API.

You can create your own stream implementation by implementing `serialization.stream.IInflateStream`.

Controlling Serialization
==============

Properties marked with the `@nostore` metadata will never be included in the serialized object. After deserialization, they will take the default value for that datatype. (This is `null` in dynamic languages.)

`@nostore` optionally takes parameter, which is the *purpose* for which the value should not be stored. The Deflater constructor options take an optional `purpose` argument. If a purpose is specified, all `@nostore` properties that specify that purpose will not be included in the serialized stream.

Example:

<pre>
    class Account {
      // Don't serialize this if we're serializing to send to the client.
      @nostore("client") public var privateKey:String;

      // Don't serialize this if we're serializing to send to the server.
      @nostore("server") public var spriteName:String;

      // NEVER serialize this.
      @nostore public var sessionID:Int;

      public function serializeForServer() : String {
        var def = new Deflater({purpose:"server"});
        def.serialize(this);
        return def.toString();
      }

      public function serializeForClient() : Stirng {
        var def = new Deflater({purpose:"client"});
        def.serialize(this);
        return def.toString();
      }
    }
</pre>

Serialization can be further customized by including a special static function on the class:

<pre>
    public static function _CLASSNAME_shouldSerializeField(cls:Class<Dynamic>, fieldName:String) : Bool;
</pre>

If this function returns false, the specified field will not be serialized.


Versioning
===============

Classes can be versioned, so that classes with added/removed fields can still be constructed from serialized data created pre-modification.

All serialized class instances include a version number, which is zero (0) by default. When fields are added removed from a class, you can increment the version number of a class and supply an upgrade function as follows:

1. Ensure the class implements `serialization.Deflatable`
2. Add a `@version` metadata to the class, specifying the current version number
3. Add a static `_upgrade_version function`, with the following signature:

<pre>
    public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String,Dynamic>) : Void;
</pre>

- `instance` is the object being deserialized, *before* any fields have been written.
- `version` is the version of the object *at the time it was serialized*.
- `fieldsMap` is a map of field name to the serialized value. This map is used after the upgrade function is called to populate the instance.

For example, imagine the following class was originally written, and instances have been serialized to a database.

<pre>
    class Player {
      public var firstName:String;
      public var lastName:String;
    }
</pre>

Later, it was decided to add an extra "xp" field to the class, and that there should be a single field for the player name, rather than firstName/lastName. The following modifications can be added to the class in order for it to still be able to deserialize old instances:

<pre>
    @version(1) class Player implements serialization.Deflatable {
      public var name:String;
      public var xp:Int;

      public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String,Dynamic>) : Void {
        if (version < 1) {
          // Add new fields to the map
          fieldsMap["name"] = fieldsMap["firstName"] + " " + fieldsMap["lastName"];
          fieldsMap["xp"] = 1;
          // fields that no longer exist MUST be removed from the map!
          fieldsMap.remove("firstName");
          fieldsMap.remove("lastName");
        }
      }
    }
</pre>


Limitations
----

* Versioning is only supported for classes. Typedefs are not versioned, and will be deserialized exactly as they were serialized.
* Fields that are removed from a type necessitate a new version and upgrade function that removes the field from the fieldMap.
* If a class is deleted, you must call `RemovedTypes.add(className)` before attempting to inflate a stream that may include that class. Removed classes will simply deserialize as `null`. Otherwise, if a class no longer exists, Inflater will throw an exception.
* Versioning is not currently supported for enums. New enum values can be added, but values cannot be removed from an `enum` definition without breaking serialized streams that include that value. If a serialized enum value no longer exists, Inflater will throw an exception.
* Changing the base class of a type is currently not supported, and will break previously serialized streams.


Inheritance
-----

* For classes using inheritance, all base classes have their own version number. 
* Each `_upgrade_version` function in the class hierarchy is called once, from the bottom of the class hierarchy to the top, for every class that has a newer version than the serialized version.
* Note that changing the version number of a base class does not affect the version number of a derived class.
* Interfaces are not versioned, as they do not affect serialization.

Custom Serialization
-----

The custom serialization methods `hxSerialize` and `hxUnserialize` are supported. Please refer to the [Haxe documentation for information](http://haxe.org/manual/std-serialization.html). Note that **versioning is not supported for these objects**, however.

Type Caching
==============

By default, a serialized object stream includes type information for the object's type, as well as any types that were referred to by the object. This includes the class name and version of the object, its base class, and the list of field names in the order they are serialized. In order to reduce size, each type is only stored once. However, it can sometimes be useful to store this type information cache separately from the serialized object itself, so that multiple streams can share it.

This type cache also stores all unique strings that appear in the serialized stream, so that strings that appear multiple times in an object are only serialized once.

The following function will serialize all objects in the input array separately, but create a single type info cache.

<pre>
    // Serialize all input objects into separate streams, with a single type cache
    function deflateObjects(objs:Array<Dynamic> results:Array<String>) : String {
      // create the stream where all strings and type information will get written
      var typeCache = new Deflater();

      for (o in objs) {
        // deflate the object, telling the deflater to store type information in typeCache instead
        var def = new Deflater({typeDeflater:typeCache});
        def.serialize(o);
        // store the deflated object
        results.push(def.toString());
      }
      
      // return the serialized type information.
      return typeCache.toString();
    }
</pre>

This function will deserialize a list of serialized objects, using an external type cache.

<pre>
    // Deserialize all input objects, using the specified type cache
    function inflateObjects(objs:Array<String>, typeCache:String) : Array<String> {
      // Inflate the type information for all objects
      var typeCache = Inflater.inflateTypeInfo(new StringInflateStream(typeCache)); 

      var results = [];
      for (o in objs) {
        // inflate the object, telling the inflater to use the type information in typeCache
        var inf = new Inflater(new StringInflateStream(o), {typeInflater:typeCache});
        results.push(inf.unserialize());
      }

      return results;
    }
</pre>
   
Additional Features
=================

The Deflater constructor take an options object with the following optional values:

<pre>
    typedef DeflaterOptions = {
      ?purpose : String,                // See "Controlling Serialization"
      ?typeDeflater : Deflater,         // See "Type Caching"
      ?stats : haxe.ds.StringMap<Int>,  // If not-null, filled with stats on the serialized object.
      ?useEnumIndex : Bool,             // Serialize enums by index instead of name. CAN BREAK VERSIONING.
      ?useCache : Bool,                 // Allow circular references between objects to be serialized correctly.
    };
</pre>

The `stats` parameter, when initialized, will be populated with each key being a class name, and the corresponding value being the total size in bytes of all instances stored of that class.

Note that useEnumIndex can break versioning if values are re-arranged in an enum definition, or new values are added to the middle of an enum definition. For that reason, it is recommended that this be set to false (the default) if the serialized data may be versioned.

Note that useCache has an impact on serialization performance, hence it is disabled by default.

//------------------------------------------------------------------------------
// Copyright 2013 Proletariat Inc. All rights reserved.
// Owner : Dan Ogles
//------------------------------------------------------------------------------
package serialization;

class RemovedTypes
{
  /** Set of types that have been removed from code, but could appear in old unserialized data.
   *  If these types are encountered, then their contents are skipped and the data is returned as null.
   */
  public static var names:Map<String,Bool> = new Map();

  public static function add(fullPath:String) : Void {
    names[fullPath] = true;
  }
}


#!/bin/sh

libname='hxInflate'
rm -f "${libname}.zip"
zip -r "${libname}.zip" haxelib.json serialization LICENSE README.md
echo "Saved as ${libname}.zip"

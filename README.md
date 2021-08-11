Converts Delphi VCL/FireMonkey style files (.vsf) to JSON

Usage:  
`Vsf2Json stylefile [outputfile]`

* `stylefile` is a Delphi .vsf file.
* `outputfile` is the target output file.  Omit it to write to stdout.

This dumps all of the .VSF metadata and objects to a structured JSON file.
Bitmaps within the file are ignored.

Requires mORMot and mORMot\sqllite3 to compile.

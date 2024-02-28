t
=

`t` is a TODO list management software to be used on the CLI. Data is
stored in JSON format in `$HOME/.config/.TODO` and
[jq](https://jqlang.github.io/jq/) is used to process the JSON file.

`t` is distributed under the MIT license (see [LICENSE](LICENSE)), and
aims to have as few dependencies as possible.


Installation
------------

Copy the `t` script to a directory in your execution path.


Usage
-----

Use `t -h` for the available options.


Dependencies
------------

Apart from `jq`, which does most of the work, `t` depend on some common
tools to work:
* `bash`
* `mktemp`
* `date`

For adding notes (`-n`) it also requires:
* `sed`
* $EDITOR should be set, or `vim` will be used.


Contributing
------------

If you find any issue,
  [report it on Github](https://github.com/rafasgj/t/issues).

If you want a feature implemented, I'm sorry, it will not be implemented.
Unless you do it yourself and
  [create a pull request](https://github.com/rafasgj/t/pulls).


Author
------

Rafael Jeffman (@rafasgj)

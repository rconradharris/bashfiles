=========
bashfiles
=========

CloudFiles with bash+curl


Fetch Script
============

Getting `bashfiles` on to a machine is as easy as using ``curl`` or ``wget``.

Curl::

    curl bashfiles.org > bashfiles
    chmod +x bashfiles
    ./bashfiles -h

Wget::

    wget bashfiles.org/bashfiles
    chmod +x bashfiles
    ./bashfiles -h


Examples
========

Download multiple objects::

    bashfiles get my-container object1 object2

Download to stdout::

    bashfiles -o - get my-container my-object > output.data

Upload from stdin::

    bashfiles -i - put my-container my-object < input.data

Move object to different container::

    bashfiles mv my-container my-object different-container my-object

Remove container with objects in it::

    bashfiles -f rmdir my-container


Features
========

* Single file using only bash, curl, and a few other POSIX utilities

* Bash-completion against commands, container-names, and object-names

* Config-file support

* Content-Type detection

* Multiple named endpoints with -e::

  bashfiles -e my-production-account get contatiner object
  bashfiles -e my-development-account get contatiner object


CloudFiles Specific Features
============================

* Large-Object Support (for files over 5 GB)

* Server-side Copy/Move

* ServiceNET support

* Checksum validation


Enable Bash Completion
======================

Choose one of these::

    bashfiles -b > ~/bash_completion.d/bashfiles.bash_completion

    bashfiles -b > /etc/bash_completion.d/bashfiles.bash_completion

    # Works for all shells
    bashfiles -b > __bfc && source __bfc && rm __bfc

    # Works in Bash 4.0 but not Bash 3.2
    source /dev/stdin <(bashfiles -b)


Credit
======

`bashfiles` is based in part on two other excellent scripts:

* Mike Barton's `cloudfiles.sh <https://github.com/redbo/cloudfiles.sh>`_
* Chmouel Boudjnah's `upcs <https://github.com/chmouel/upcs>`_


Authors
=======

* Rick Harris

=========
bashfiles
=========

``bashfiles`` is a command-line client for interacting with CloudFiles. Its
main goals are to be a single, easy to fetch file that only has minimal
dependencies, namely ``bash`` and ``curl``.

Bashfiles works particularly well on machines with limited userspace tools
(for example the Dom0 of a Xen host). However, it's featureful enough to be
useful anywhere.


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


Download an object from CloudFiles::

    bashfiles get my-container object1

Upload an object to CloudFiles from stdin::

    bashfiles -i - put my-container my-object < input.data

Move object to different container::

    bashfiles mv my-container my-object different-container my-object

Remove container with objects in it::

    bashfiles -f rmdir my-container

Create temporary links (files available on the CDN that self-destruct after
one hour)::

    bashfiles tmplink my-object


Features
========

* Single file using only bash, curl, and a few other POSIX utilities

* Bash-completion against commands, container-names, and object-names

* Config-file support

* Content-Type detection

* Multiple named endpoints with -e::

  bashfiles -e my-production-account get contatiner object
  bashfiles -e my-development-account get contatiner object

* ... or set default endpoint::

  bashfiles endpoint default my-development account


CloudFiles Specific Features
============================

* Large-Object Support (for files over 5 GB)

* Server-side Copy/Move

* ServiceNET support

* Checksum validation

* CDN support


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

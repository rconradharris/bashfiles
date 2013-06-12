==============
cloudfiles2.sh
==============

CloudFiles with bash+curl


Features
========

* Commands: cp, get, ls, mkdir, mv, put, rm, rmdir, stat

* Bash-completion against commands, container-names, and object-names (this
  saves *so* much typing!)

* Config-file support (``~/.cloudfiles.sh``)

* Progress meter (with -q to disable it)

* ServiceNET support

* Checksum validation

* Large-Object Support (Dynamic Large Objects)

* Clear and remove a container with cloudfiles.sh -f rmdir <my-container>

* Specify destination filename or output directly to stdout

* Server-side Copy/Move


Enable Bash Completion
======================

Choose one of these::

    bashfiles -b ~/bash_completion.d/bashfiles.bash_completion

    bashfiles -b /etc/bash_completion.d/bashfiles.bash_completion

    # Works for all shells
    bashfiles -b > __bfc && source __bfc && rm __bfc

    # Works in Bash 4.0 but not Bash 3.2
    source /dev/stdin <(bashfiles -b)


Credit
======

cloudfiles2.sh is in large part based two other excellent scripts, Mike
Barton's `cloudfiles.sh <https://github.com/redbo/cloudfiles.sh>`_ and Chmouel
Boudjnah's `upcs <https://github.com/chmouel/upcs>`_.

Authors
=======

    * Rick Harris
    * Mike Barton
    * Chmouel Boudjnah
    * Jay Payne

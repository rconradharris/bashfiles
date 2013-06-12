=========
bashfiles
=========

CloudFiles with bash+curl


Features
========

* Single file using only bash, curl, and a few other POSIX utilities

* Bash-completion against commands, container-names, and object-names

* Config-file support (``~/.cloudfiles.sh``)


CloudFiles Specific Features
============================

* Large-Object Support (for files over 5 GB)

* ServiceNET support

* Checksum validation

* Server-side Copy/Move


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

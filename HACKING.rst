* Use long-options whenever possible (e.g. prefer ``--upload-file`` over ``-T``)

* Use ``local`` variables

* Logic should be encapsulated in functions wherever possible (bears repeating
  since this is bash)

* Use `PEP8 <http://www.python.org/dev/peps/pep-0008/>`_ whitespace rules (4
  space indent, 2 blank lines between functions)

* Limit line-length to <= 78 characters

* Prefer ``if`` statements over short-circuiting, e.g.:

  RATHER NOT
  ::

      [[ -r $config ]] && source $config

  INSTEAD
  ::

      if [[ -r $config ]]; then
          source $config
      fi

* Within functions, set arguments to meaningful names:

  RATHER NOT
  ::

      function foo() {
          rm $1
      }

  INSTEAD
  ::

      function foo() {
          local filename=$1
          rm $filename
      }

* Use ```foo``` for one-liners and ``$(foo | bar)`` for multi-liners

* When order doesn't matter, default to alphabetical order

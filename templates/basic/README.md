# {{title}}

A [Littoral](https://github.com/lispnik/littoral) application.

```sh
make test    # FiveAM tests, through Littoral's fake browser
make run     # the development server on http://127.0.0.1:{{port}}/
make build   # bin/{{name}}, a standalone executable
```

`make run` serves in development mode, with the toolbar and halos for
inspecting components; edit `render` in `src/app.lisp`, recompile it
(`C-c C-c` in Emacs) and the open page redraws itself. From a REPL instead:

```lisp
(asdf:load-system :{{name}})
({{name}}:serve)
```

## What's here

- `src/app.lisp`: `front-page`, the root component, with a counter, a
  confirmation dialog shown with `show`, and a form. `serve` registers it
  and starts the server.
- `tests/app.lisp`: tests that click through it in-process.
- `Makefile`: finds Littoral through `LITTORAL` (now `{{littoral}}`).

More dependencies: `ocicl install <system>`, then add it to `:depends-on`
in `{{name}}.asd`.

## Next

[The Littoral tutorial](https://lispnik.github.io/littoral/tutorial.html)
builds a reading list one idea at a time, and
[the guide](https://lispnik.github.io/littoral/) covers the rest: tasks,
AJAX, server push, descriptions, a database, signing in and translations.

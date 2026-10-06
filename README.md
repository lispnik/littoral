# Littoral

Littoral is a Common Lisp port of Smalltalk's [Seaside](https://seaside.st) web framework. You build an application from stateful components instead of routes and templates:

- Links and buttons carry closures (**callbacks**), not URLs you design.
- One component can **call** another and get its **answer** back.
- The **back button** restores the state each page was rendered from.
- **Tasks** describe a multi-page flow as straight-line code.

It runs on SBCL and serves through Clack (Hunchentoot by default). Dependencies are managed with ocicl.

```lisp
(defpackage #:hello (:use #:cl #:littoral #:littoral.html))
(in-package #:hello)

(defclass counter (component)
  ((count :initform 0 :accessor count-of)))

(defmethod states ((self counter)) (list self))   ; backtrack COUNT

(defmethod render ((self counter))
  (h1 () (text (count-of self)))
  (anchor (:callback (lambda () (incf (count-of self)))) "++")
  (anchor (:callback (lambda () (decf (count-of self)))) "--"))

(register-application "/counter" 'counter)
(start :port 8080)
```

## Running

```sh
make test          # FiveAM suite, in-process, no sockets
make run           # examples on http://127.0.0.1:8080/
```

The example applications are under `/examples/…`: counter, multi-counter, guess (a task), login (call/answer with validation), ajax and todo. The configuration application is at `/config`.

## Concepts

| Seaside                         | Littoral                                        |
|---------------------------------|-------------------------------------------------|
| `renderContentOn: html`         | `(defmethod render ((self c)) …)`               |
| `html div class: 'x'; with: […]` | `(div (:class "x") …)`                          |
| `html anchor callback: […]; with: 'go'` | `(anchor (:callback (lambda () …)) "go")` |
| `html textInput on: #name of: self` | `(text-input (:value … :callback (lambda (v) …)))` |
| `html render: child`            | `(render-component child)`                      |
| `children`, `states`            | `children`, `states` generics                   |
| `self call: c` / `self answer: x` | `(call self c)` / `(answer c x)`              |
| `show:onAnswer:`                | `(show self c :on-answer fn)`                   |
| `WATask>>go`                    | `(define-flow my-task (self) …)`                |
| `inform:` `confirm:` `request:` `chooseFrom:` | `inform` `confirm` `request-input` `choose-from` |
| decorations                     | `add-decoration`, `form-decoration`, `validate-with`, … |
| `updateRoot:`, `style`, `script` | `update-root`, `style`, `script`                |
| jQuery `load html:`             | `:on-click (ajax :callback … :update component)` |

### HTML

The tag and brush macros are in the `littoral.html` package. They live in their own package because names such as `main`, `header`, `label` and `table` are too common to push onto every package that uses `littoral`. A tag's first argument is its attribute plist, and you can omit it. Literal strings in a tag body are written as escaped text. To write any other value, call `text` (escaped) or `raw` (unescaped).

The brushes are `anchor`, `form`, `text-input`, `password-input`, `number-input`, `hidden-input`, `text-area`, `checkbox`, `select-list`, `radio-group`, `submit-button` and `button`. Each takes a `:callback`. When a form is submitted, the field callbacks run first, in render order, and the button's action runs after them.

### Request cycle

Littoral follows Seaside's request cycle. A request that names callbacks goes through these steps:

1. Restore the snapshot of the page the request came from.
2. Run the callbacks.
3. Snapshot the result as a new page (`_k`).
4. Redirect to that new page.

A request that names no callbacks renders the page. Pages are snapshots of the visible components' decorations, plus the slots of every object named by their `states` methods. Because of this, both going back and acting on an old page work the way they do in Seaside.

### Tasks and continuations

Common Lisp has no first-class continuations. `define-flow` therefore rewrites the flow body in continuation-passing style with [cl-cont](https://github.com/ocicl/cl-cont), and each `call` suspends the flow until the called component answers. The rewrite has some limits:

- Don't put `call` inside `unwind-protect`, `catch` or `handler-case`.
- If you `setq` a variable after a `call`, every page that resumes from that call shares the change. Prefer fresh bindings when the back button matters.

Outside a flow, `call` shows the component and returns immediately. Use `show` with `:on-answer` there.

### AJAX

To make a component re-renderable in place, mix `updatable` into its class. Then give an element an `:on-click`, `:on-change` or `:on-input` attribute whose value is `(ajax :callback thunk :update component)`. Use `(periodical seconds :update component)` instead to re-render on a timer. `static/littoral.js` is small and has no dependencies; it posts the request and swaps the HTML.

### Development tools

Applications in `:development` mode, the default, end each page with a toolbar:

- **New Session**
- **Configure**: opens `/config`.
- **Halos**: frames every component, with buttons to inspect and edit its slots or to view its HTML source.
- **Sessions**: a session browser.
- The render time.

`/config` lists the registered applications. From there you can add, remove and configure them (title, root class, mode, session timeout, pages kept, cookie sessions) and browse their sessions. Use `(configure-admin :user "u" :password "p")` to put it behind HTTP basic auth.

### Configuration

```lisp
(register-application "/shop" 'shop-root
  :title "Shop"
  :mode :deployment          ; no toolbar or halos
  :session-timeout 1800      ; seconds idle
  :max-continuations 50      ; pages the back button can reach
  :cookie-sessions t         ; session key in a cookie, not the URL
  :stylesheets '("/static/shop.css")
  :credentials '("user" . "password"))
```

`(make-lack-app)` returns a plain Lack application you can mount into a larger Lack/Clack stack. Set `*debug-errors*` to enter the debugger on errors instead of rendering an error page.

## License

MIT

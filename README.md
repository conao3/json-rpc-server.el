<p align=center>
    <img src="media/logo.png" alt="json-rpc-server logo" />
</p>

<h1 align=center>JSON-RPC-Server</h1>

<p align=center>Server-side implementation of the JSON-RPC 2.0 protocol for Emacs.</p>

<p align=center>
<!-- This is an emoticon. Don't delete it if it doesn't show up in your editor. -->
🔌
</p>

---

<!-- ## What is this Package? -->

This is a full implementation of the [JSON-RPC
2.0](https://www.jsonrpc.org/specification) protocol for Emacs. You pass in a
JSON string, Emacs executes the specified function(s), and a JSON-RPC 2.0
response is returned.

This package is designed sit underneath a transport layer. <b>No transport logic
is included.</b> A separate transport layer needs to be used to communicate with
external clients. Since JSON-RPC provides [no inbuilt
mechanism](https://groups.google.com/d/msg/json-rpc/PN462g49yL8/DdMa93870_oJ) for
authenticating requests, the transport layer should also handle authentication.

The default transport layer uses the http protocol, and is available
[here](http://www.github.com/jcaw/http-rpc-server.el).


---


<!-- markdown-toc start - Don't edit this section. Run M-x
     markdown-toc-refresh-toc Please note that the markdown generator doesn't
     work perfectly with a centered heading, as above. It will need manual
     tweaking -->

## Table of Contents

- [How it Works](#how-it-works)
    - [Example: Calling a Method](#example-calling-a-method)
    - [Example: Malformed JSON](#example-malformed-json)
    - [Example: Invalid Request](#example-invalid-request)
- [Datatype Limitations](#datatype-limitations)
    - [Other Types](#other-types)
- [Installation](#installation)
- [List of Transport Layers](#list-of-transport-layers)
- [FAQ](#faq)

<!-- markdown-toc end -->


## How it Works

Functions in this package are prefixed with `jrpc-`.

`jrpc-handle` is the main entry point into the package. 

```emacs-lisp
;; This will decode a JSON-RPC 2.0 request, execute it, and return the JSON-RPC 2.0 response.
(jrpc-handle string-encoded-json-rpc-request)
```

If an error occurs, the response will be a string containing a JSON-RPC 2.0
error response.

Only functions you have specifically exposed can be called via RPC. To expose a
function, call `jrpc-expose function`. For example:

```emacs-lisp
;; This will allow the `+' function to be called via JSON-RPC.
(jrpc-expose-function '+)
```

You can also expose functions manually by adding them to `jrpc-exposed-functions`.

### Examples

#### Example: Calling a Method

Encode a request according to the JSON-RPC 2.0 protocol. `method` should be the method name, as a string.

Here's an example request:

```json
{
    "jsonrpc": "2.0",
    "method": "+",
    "params": [1, 2, 3],
    "id": 29492,
}
```

Let's encode this into a string and pass it to `jrpc-handle`:

```emacs-lisp
(jrpc-handle
 "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"+\",
    \"params\": [1,2,3],
    \"id\": 29492
}")
```

`json-rpc-server` will decode the request, then apply the function `+` to the
list `'(1, 2, 3)`. Here's what the result of `jrpc-handle` will be:

```emacs-lisp
"{\"jsonrpc\":\"2.0\",\"result\":6,\"id\":29492}"
```

Decoded:

```json
{
    "jsonrpc": "2.0",
    "result": 6,
    "id": 29492
}
```

This string-encoded response can now be returned to the client.

#### Example: Malformed JSON

If there is a problem with the request (or another error occurs), a `jrpc-handle` will encode a JSON-RPC 2.0 error response. Here's an example.

Let's try some malformed JSON:

```json
{Szx. dsd}
```

The call to `jrpc-handle`:

```emacs-lisp
(jrpc-handle "{Szx. dsd}")
```

Here's what `jrpc-handle` returns:

```emacs-lisp
"{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"There was an error decoding the request's JSON.\",\"data\":{\"underlying-error\":{\"json-string-format\":[\"doesn't start with `\\\"'!\"]}}},\"id\":null}"
```

Decoded:

```json
{
    "jsonrpc": "2.0",
    "error": {
        "code": -32700,
        "message": "There was an error decoding the request's JSON.",
        "data": {
            "underlying-error": {
                "json-string-format": ["doesn't start with `\"'!"]
            }
        }
    },
    "id": null
}
```

Note the `"data"` field. Some responses are triggered by an underlying error in
the Elisp, which may contain more meaningful information about the error. When
possible, the contents of that error will be returned in the
`"underlying-error"` field. If there is no underlying error, this field will not
be present.

#### Example: Invalid Request

This time, let's try an invalid request.

```json
{
    "params": [1, 2, 3],
    "id": 23092
}
```

The call to `jrpc-handle`:

```emacs-lisp
(jrpc-handle 
 "{
    \"params\": [1, 2, 3],
    \"id\": 23092
}")
```

Here's what `jrpc-handle` returns:

```emacs-lisp
"{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"`method` was not provided.'\",\"data\":null},\"id\":23092}"
```

Decoded:

```json
{
    "jsonrpc": "2.0",
    "error": {
        "code": -32600,
        "message": "`method` was not provided.",
        "data": null
    },
    "id": 23092
}
```

Note the `id` field. `jrpc-handle` will do its best to extract an `id` from all
requests, even invalid requests, so errors can be synced up to their respective
requests.

## Datatype Limitations

The structure of JSON limits the types of variables that can be transferred.
JSON only contains six datatypes. Thus, functions exposed by this protocol
<b>must expect certain datatypes.</b> 

The datatypes are mapped as follows:

| JSON Datatype            | Decodeded Elisp Datatype |
| ---                      | ---                      |
| string (keys)            | symbol                   |
| string (everywhere else) | string                   |
| number                   | integer or float         |
| boolean                  | `t` or `:json-false`     |
| null                     | nil                      |
| object                   | alist (with symbol keys) |
| array                    | list                     |

You may notice that keys are decoded differently to other strings. Here's what
that means. This JSON:

```json
{
    "first-key": "first-value",
    "second-key": ["two", "values"],
}
```

Will be decoded into this alist:

```emacs-lisp
'((first-key . "first-value")
  (second-key . '("two" "values")))
```

Please note that empty JSON arrays will be translated into empty Elisp lists,
which are the same as `nil`.

### Other Types

Because of these type limitations, you cannot transfer vectors, plists, hash tables,
cl-structs, etc.

There is no easy way around this. JSON-RPC provides simplicity, at the cost of
flexibility. If you want to call a function that expects a different type, you
must write an intermediary function that translates from the available ones and
publish that instead.

## Installation

It will be installable from MELPA once I persuade them to add it.

## List of Transport Layers

If you want to actually make RPC calls to Emacs, you need to use a transport
layer. Here's a list:

| Project                                                            | Protocol |
| -------                                                            | -------- |
| [`http-rpc-server`](http://www.github.com/jcaw/http-rpc-server.el) | HTTP     |

Have you written one? Open a pull request and I'll add it.

## FAQ

- <b>Does it support batch requests?</b> Yes. Pass in an encoded list of
  requests to execute each in turn.
- <b>Is it compatible with older versions of JSON-RPC?</b> Yes. It should accept
  and work fine with older JSON-RPC requests. However, they aren't officially
  supported and the response will still be JSON-RPC 2.0.
- <b>Does it support keyword arguments</b> Not currently, no. Support will be
  added for this in the future.
- <b>How can I send a [vector, hash table, etc]?</b> You can't. You have to
  write an intermediate function that constructs these types from alists,
  strings, etc.
- <b>Does it support notifications?</b> No. All requests block until a value is
  returned (or an error occurs). This could be implemented at the transport
  level, if desired.
- <b>Can I run multiple servers at once?</b> No. One server per session. This
  could be added in the future if it's a feature people really want.
- <b>Are you open to pull requests?</b> Yes!

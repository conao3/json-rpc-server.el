;;; json-rpc-server-rpc-layer-test.el --- Tests for json-rpc-server


(require 'ert)

(load-file "json-rpc-server-rpc-layer.el")


;; Unit tests
(progn
  ;; TODO: Find how to organize Elisp tests hierarchically.
  (ert-deftest test-jrpc--validate-request ()
    "Test for `jrpc--validate-request'.

Test whether it accepts good requests, and raises the
correct errors for flawed requests.

Note that when testing for raised errors, it doesn't test error
messages - it just tests the class of the signal."
    ;; Valid request, all fields filled.
    ;;
    ;; We also use this test to ensure the request is returned.
    (let ((request '((jsonrpc . "2.0")
                     (method . "message")
                     (params . ("This is a %s"
                                "test message"))
                     (id . 12456))))
      (should (equal (jrpc--validate-request request)
                     request)))
    ;; Valid request, but it's jsonrpc 1.0
    (should (jrpc--validate-request
             '((method . "message")
               (params . ("This is a %s"
                          "test message"))
               (id . 12456))))
    ;; Valid request, but there's no params.
    (should (jrpc--validate-request
             '((jsonrpc . "2.0")
               (method . "message")
               (id . 12456))))

    ;; Invalid `jsonrpc' param
    (progn
      ;; jsonrpc is 3.0 - too high
      (should-error (jrpc--validate-request
                     '((jsonrpc . "3.0")
                       (method . "message")
                       (id . 12456)))
                    :type 'jrpc-invalid-request)
      ;; jsonrpc is 2 - formatted wrong
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2")
                       (method . "message")
                       (id . 12456)))
                    :type 'jrpc-invalid-request))

    ;; Invalid `method' param
    (progn
      ;; No method
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2.0")
                       (id . 12456)))
                    :type 'jrpc-invalid-request)
      ;; Wrong type for method
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2.0")
                       (method . 120983)
                       (id . 12456)))
                    :type 'jrpc-invalid-request))

    ;; Invalid `params' param
    (progn
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2.0")
                       (method . "message")
                       (params . "Just a string param")
                       (id . 12456)))
                    :type 'jrpc-invalid-request))

    ;; Invalid `id' param
    (progn
      ;; No id
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2.0")
                       (method . "message")))
                    :type 'jrpc-invalid-request)
      ;; Invalid id type - in this case, a string.
      (should-error (jrpc--validate-request
                     '((jsonrpc . "2.0")
                       (method . "message")
                       (id . "12456")))
                    :type 'jrpc-invalid-request))
    )

  (ert-deftest test-jrpc--decode-request-json ()
    "Test for `jrpc--decode-request-json'.

Test whether it decodes json correctly, in the way I want.

Note that this does not test the functionality of `json.el'. It
only tests the additional conditions imposed by the
`jrpc--decode-request-json' method."
    ;; List decoding
    (progn
      ;; Simple members
      (should (equal (jrpc--decode-request-json
                      "[1, 2, 3]")
                     '(1 2 3)))
      (should (equal (jrpc--decode-request-json
                      "[\"first\", \"second\", \"third\"]")
                     '("first" "second" "third"))))

    ;; Index and object decoding.
    ;;
    ;; Indexes should be symbols, and the result should be an alist.
    (should (equal (jrpc--decode-request-json
                    "{\"index1\": \"value1\", \"index2\": \"value2\"}")
                   '((index1 . "value1")
                     (index2 . "value2"))))

    ;; Malformed json should raise a specific error, so it can be caught.
    (should-error (jrpc--decode-request-json
                   ;; Some malformed JSON input.
                   "als;d'asfoasf")
                  :type 'jrpc-invalid-request-json)

    ;; Try decoding a full request
    (should (equal
             (jrpc--decode-request-json "{\"jsonrpc\": \"2.0\",\"method\": \"message\",\"params\": [\"This is a %s\", \"test message\"],\"id\": 12456,}")
             '((jsonrpc . "2.0")
               (method . "message")
               (params . ("This is a %s"
                          "test message"))
               (id . 12456))))
    )

  (ert-deftest test-jrpc--execute-request ()
    "Test for `jrpc--execute-request'.

Note that this while this test does test a full function
execution, it does not do so thoroughly. That is done in the unit
test for the underlying function, `jrpc--call-function'.

This test is primarily designed to check that the function is
correctly parsed and sent into `jrpc--call-function'."
    (defun jrpc--call-function-patch (func args)
      "Patched `jrpc--call-function' that just checks the types of the arguments."
      (should (symbolp func))
      ;; Note that nil counts as a list.
      (should (listp args)))

    ;; Mock `jrpc--call-function' for these methods
    (cl-letf (((symbol-function 'jrpc--call-function)
               'jrpc--call-function-patch))
      ;; Check it executes okay with a simple method call
      (jrpc--execute-request '((method . "message")
                               (params . ("this is a %s message"
                                          "test"))
                               (id     . 1)))
      ;; Check it executes okay no arguments
      (jrpc--execute-request '((method . "message")
                               (id     . 1))))

    ;; Temporarily expose `+' and ensure it executes correctly.
    (let ((jrpc-exposed-functions '(+)))
      (should (= (jrpc--execute-request '((method . "+")
                                          (params . (1 2 3))
                                          (id     . 1)))
                 6))))


  (ert-deftest test-jrpc-internal-error-response ()
    "Test for `jrpc-internal-error-response'.

Tests the correct JSON is constructed, and the correct errors raised."
    ;; Check a simple message.
    (should (cl-equalp (json-read-from-string
                        (jrpc-internal-error-response "This is a test"))
                       '((jsonrpc . "2.0")
                         (error   . ((code    . -32700)
                                     (message . "This is a test")
                                     (data    . nil)))
                         (id      . nil))))

    ;; Check a request that holds an id
    (should (cl-equalp (json-read-from-string
                        (jrpc-internal-error-response
                         "This is a test"
                         "{\"method\": \"message\",\"id\": 12456,}"
                         ))
                       '((jsonrpc . "2.0")
                         (error   . ((code    . -32700)
                                     (message . "This is a test")
                                     (data    . nil)))
                         (id      . 12456))))

    ;; Check wrong message types
    (progn
      (should-error (jrpc-internal-error-response nil)
                    :type 'error)
      (should-error (jrpc-internal-error-response 1)
                    :type 'error)
      (should-error (jrpc-internal-error-response '(("an" . "alist")))
                    :type 'error))

    ;; Check wrong JSON types
    ;;
    ;; These forms should execute without issue, but they should NOT contain an
    ;; id.
    (progn
      ;; nil JSON
      (should (not
               (alist-get
                'id
                (json-read-from-string
                 (jrpc-internal-error-response "This is a test" nil)))))
      ;; Wrong JSON structure
      (should (not
               (alist-get
                'id
                (json-read-from-string
                 (jrpc-internal-error-response "This is a test" "12980")))))
      ;; Non-string JSON
      (should (not
               (alist-get
                'id
                (json-read-from-string
                 (jrpc-internal-error-response "This is a test" 12980))))))
    )

  (ert-deftest test-jrpc--decode-id ()
    "Test for `jrpc--decode-id'.

Tests that it decodes the id in minimalistic JSON, and also that
it does not block with errors when it cannot decode the id."
    ;; It should extract the id even if the overall request is invalid.
    (should (eq (jrpc--decode-id "{\"id\": 10249}")
                10249))

    ;; These are all invalid JSON, so they should return nil. Nothing should
    ;; raise an error.
    (progn
      ;; Null id
      (should (eq (jrpc--decode-id "{\"id\": null}")
                  nil))
      ;; Invalid id type: string
      (should (eq (jrpc--decode-id "{\"id\": \"10249\"}")
                  nil))
      ;; Invalid id type: object (dictionary)
      (should (eq (jrpc--decode-id "{\"id\": {\"nested\": \"dict\"}}")
                  nil)))
    )
  )


;; Integration tests
(progn
  ;; None yet.

  (ert-deftest test-full-procedure-call--to-+ ()
    "Test a valid procedure call to `+'.

Note that `+' is a command that doesn't change the editor's
state. Thus this checks a limited type of functionality."
    ;; Temporarily expose "+"
    (let ((jrpc-exposed-functions '(+)))
      ;; Get the response first, then progressively check each part of its
      ;; contents.
      (let ((response (json-read-from-string
                       (jrpc-handle
                        (json-encode
                         '(("jsonrpc" . "2.0")
                           ("method"  . "+")
                           ("params"  . [1 2 3])
                           ("id"      . 21145)))))))
        ;; Check each component, *then* check the full structure. We do this to
        ;; make it easier to pinpoint why the test is failing.
        (should (equal (alist-get 'jsonrpc response)
                       "2.0"))
        (should (eq (alist-get 'result response)
                    6))
        ;; The JSON-RPC 2.0 specification indicates that, on a successful
        ;; response, the `error' parameter should not be present in the response
        ;; at all. It cannot simply be null - it should not be there.
        (should (eq (assoc 'error response)
                    nil))
        (should (eq (alist-get 'id response)
                    21145))
        ;; Since Elisp has no reliable way of comparing alists with the same
        ;; elements in different orders, this is sensitive to the *order* of the
        ;; JSON object returned. The test will fail if the order changes. Not
        ;; perfect.
        (should (cl-equalp response
                           '((jsonrpc . "2.0")
                             (result  . 6)
                             (id      . 21145))))))
    )

  (ert-deftest test-full-procedure-call--changing-internal-state ()
    "Test a valid procedure call that just changes a variable.

This test is designed to test an internal state change. It tests
relatively minimal stay changing functionality. Only a variable
is changed - things like the buffer should be unaffected."
    ;; We have to define a function to change the variable, that takes a string
    ;; name as input, since we can't transfer symbols via JSON.
    (defun jrpc-custom-setq (var-name new-value)
      (set (intern var-name) new-value))
    (let (
          ;; Temporarily expose this function
          (jrpc-exposed-functions '(jrpc-custom-setq))
          ;; This is the variable we will try to change
          (test-var 10298)
          )
      (jrpc-handle
       (json-encode
        '(("jsonrpc" . "2.0")
          ("method"  . "jrpc-custom-setq")
          ("params"  . ["test-var" "this is a test string"])
          ("id"      . 21145))))
      (should (string= test-var
                       "this is a test string"))))

  (ert-deftest test-full-procedure-call--changing-buffer ()
    "Test a valid procedure call to `insert', with a temp buffer.

This test is designed to test functionality that changes the
state of the buffer.

This only tests the change in the buffer - other tests are
responsible for checking the actual response of the API."
    ;; Temporarily expose `insert'
    (let ((jrpc-exposed-functions '(insert)))
      (with-temp-buffer
        (jrpc-handle
         (json-encode
          '(("jsonrpc" . "2.0")
            ("method"  . "insert")
            ("params"  . ["this is a test string"])
            ("id"      . 21145))))
        (should (string= (buffer-string)
                         "this is a test string"))))
    )

  (ert-deftest test-full-procedure-call--unexposed-function ()
    "Test a procedure call to a function that hasn't been exposed.

This test is designed to test two things:

  1. The error type of a function that has not been exposed. This
     should match the JSON-RPC 2.0 specification. Specifically,
     the error code needs to match.

  2. The structure of an error response.

Other integration tests will check other error codes, but they
won't check the structure of the response. It is assumed that
this test is sufficient to check that for other error codes."
    ;; Temporarily expose no functions
    (let ((jrpc-exposed-functions '()))
      ;; Get the response first, then progressively check each part of its
      ;; contents.
      (let* ((response (json-read-from-string
                        (jrpc-handle
                         (json-encode
                          '(("jsonrpc" . "2.0")
                            ("method"  . "+")
                            ("params"  . [1 2 3])
                            ("id"      . 21145))))))
             (response-error (alist-get 'error response)))
        (should response)
        ;; Check each component, *then* check the full structure. We do this to
        ;; make it easier to pinpoint why the test is failing.
        (should (equal (alist-get 'jsonrpc response)
                       "2.0"))
        ;; The JSON-RPC 2.0 specification indicates that, when an error is
        ;; raised, the `result' parameter should not be present in the response
        ;; at all. It cannot simply be null - it should not be there.
        (should (eq (assoc 'result response)
                    nil))
        (should (eq (alist-get 'id response)
                    21145))
        (should (eq (alist-get 'code response-error)
                    ;; This error code corresponds to "method not found" in the
                    ;; JSON-RPC 2.0 specification.
                    -32601))
        (should (eq (alist-get 'data response-error)
                    nil))
        ;; We don't check the exact string
        (should (stringp (alist-get 'message response-error))))))

  (ert-deftest test-full-procedure-call--non-existant-function ()
    "Test a procedure call to a function that has been exposed, but doesn't exist.

This test is designed to trick the system up by making it think
it is calling a valid function, causing an unexpected error when
the function is invoked."
    (let ((jrpc-exposed-functions '(jrpc-function-that-does-not-exist)))
      (let* ((response (json-read-from-string
                        (jrpc-handle
                         (json-encode
                          '(("method"  . "jrpc-function-that-does-not-exist")
                            ("id"      . 1))))))
             (response-error (alist-get 'error response)))
        (should response)
        ;; We only check the response code
        (should (eq (alist-get 'code response-error)
                    ;; This error code corresponds to "method not found" in the
                    ;; JSON-RPC 2.0 specification.
                    -32601)))))

  (ert-deftest test-full-procedure-call--empty-json ()
    "Test a procedure call with empty JSON."
    (let* ((response (json-read-from-string
                      (jrpc-handle "{}")))
           (response-error (alist-get 'error response)))
      (should response)
      (should (eq (alist-get 'code response-error)
                  ;; This error code corresponds to "invalid request" in the
                  ;; JSON-RPC 2.0 specification.
                  -32600))))
  )


;;; json-rpc-server-rpc-layer-test.el ends here

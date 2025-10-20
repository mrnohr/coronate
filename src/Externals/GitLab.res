/*
  Copyright (c) 2021 John Jackson.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

// Simple fetch-based GitLab API client
type response<'a> = {
  status: int,
  data: 'a,
}

// Fetch bindings
@val external fetch: (string, 'a) => Promise.t<'b> = "fetch"
type fetchResponse
@send external json: fetchResponse => Promise.t<Js.Json.t> = "json"

module Snippet = {
  type file = {
    id: string,
    title: string,
    updated_at: Js.Date.t,
  }

  type snippetFile = {
    content: string,
  }

  type snippetData = {
    title: string,
    files: array<{"file_path": string, "content": string}>,
  }

  let apiCall = (~token, ~method, ~url, ~body=?, ()) => {
    let headers = Js.Dict.fromArray([
      ("PRIVATE-TOKEN", token),
      ("Content-Type", "application/json"),
    ])

    let init = Js.Dict.fromArray([
      ("method", method->Obj.magic),
      ("headers", headers->Obj.magic),
    ])

    switch body {
    | Some(b) => Js.Dict.set(init, "body", Js.Json.stringify(b)->Obj.magic)
    | None => ()
    }

    fetch(url, init->Obj.magic)->Promise.then(json)
  }

  // Extract snippet ID from various GitLab URL formats
  let extractSnippetId = url => {
    // Matches: https://gitlab.com/snippets/123456
    // Or: https://gitlab.com/-/snippets/123456
    // Or just: 123456
    let patterns = [
      %re("/snippets\/(\d+)/"),
      %re("/^(\d+)$/"),
    ]

    patterns
    ->Belt.Array.reduce(None, (acc, pattern) => {
      switch acc {
      | Some(_) => acc
      | None =>
        switch Js.Re.exec_(pattern, url) {
        | Some(result) =>
          switch Js.Re.captures(result)->Belt.Array.get(1) {
          | Some(capture) => Js.Nullable.toOption(capture)
          | None => None
          }
        | None => None
        }
      }
    })
  }

  let list = (~token) => {
    apiCall(~token, ~method="GET", ~url="https://gitlab.com/api/v4/snippets", ())
    ->Promise.thenResolve(data => {
      data
      ->Js.Json.decodeArray
      ->Belt.Option.getWithDefault([])
      ->Belt.Array.map(x => {
        let obj = Js.Json.decodeObject(x)->Belt.Option.getWithDefault(Js.Dict.empty())
        {
          title: obj
            ->Js.Dict.get("title")
            ->Belt.Option.flatMap(Js.Json.decodeString)
            ->Belt.Option.getWithDefault("Untitled"),
          id: obj
            ->Js.Dict.get("id")
            ->Belt.Option.flatMap(Js.Json.decodeNumber)
            ->Belt.Option.map(Belt.Float.toString)
            ->Belt.Option.getWithDefault(""),
          updated_at: obj
            ->Js.Dict.get("updated_at")
            ->Belt.Option.flatMap(Js.Json.decodeString)
            ->Belt.Option.map(Js.Date.fromString)
            ->Belt.Option.getWithDefault(Js.Date.make()),
        }
      })
    })
  }

  let write = (~token, ~id, ~data, ~minify) => {
    let content = if minify {
      Js.Json.stringify(data)
    } else {
      Js.Json.stringifyWithSpace(data, 2)
    }

    // Use "update" action for existing files
    let body = Js.Dict.fromArray([
      ("title", Js.Json.string("coronate-data")),
      ("files", Js.Json.array([
        Js.Dict.fromArray([
          ("action", Js.Json.string("update")),
          ("file_path", Js.Json.string("coronate-data.json")),
          ("content", Js.Json.string(content)),
        ])->Js.Json.object_
      ])),
    ])->Js.Json.object_

    apiCall(
      ~token,
      ~method="PUT",
      ~url="https://gitlab.com/api/v4/snippets/" ++ id,
      ~body,
      (),
    )
  }

  let read = (~token, ~id) => {
    apiCall(~token, ~method="GET", ~url="https://gitlab.com/api/v4/snippets/" ++ id, ())
    ->Promise.thenResolve(x => {
      let obj = Js.Json.decodeObject(x)->Belt.Option.getWithDefault(Js.Dict.empty())
      let files = obj
        ->Js.Dict.get("files")
        ->Belt.Option.flatMap(Js.Json.decodeArray)
        ->Belt.Option.getWithDefault([])

      let firstFile = files->Belt.Array.get(0)
      switch firstFile {
      | Some(file) => {
          let fileObj = Js.Json.decodeObject(file)->Belt.Option.getWithDefault(Js.Dict.empty())
          fileObj
            ->Js.Dict.get("content")
            ->Belt.Option.flatMap(Js.Json.decodeString)
            ->Belt.Option.getWithDefault("")
        }
      | None => ""
      }
    })
  }

  let create = (~token, ~data, ~minify) => {
    let content = if minify {
      Js.Json.stringify(data)
    } else {
      Js.Json.stringifyWithSpace(data, 2)
    }

    let body = Js.Dict.fromArray([
      ("title", Js.Json.string("coronate-data")),
      ("visibility", Js.Json.string("private")),
      ("files", Js.Json.array([
        Js.Dict.fromArray([
          ("file_path", Js.Json.string("coronate-data.json")),
          ("content", Js.Json.string(content)),
        ])->Js.Json.object_
      ])),
    ])->Js.Json.object_

    apiCall(~token, ~method="POST", ~url="https://gitlab.com/api/v4/snippets", ~body, ())
  }
}

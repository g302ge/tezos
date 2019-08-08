(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2019 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

open Worker

module Make
    (Event : EVENT)
    (Request : REQUEST)  = struct

  module Event = Event
  module Request = Request

  type status =
      WorkerEvent of Event.t
    | Request of Request.view
    | Terminated
    | Timeout
    | Crashed of error list
    | Started of string option
    | Triggering_shutdown
    | Duplicate of string

  type t = status Time.System.stamped

  let status_encoding =
    let open Data_encoding in
    Time.System.stamped_encoding @@
    union
      [ case (Tag 0)
          ~title: "Event"
          Event.encoding
          (function WorkerEvent e -> Some e | _ -> None)
          (fun e -> WorkerEvent e) ;
        case (Tag 1)
          ~title: "Request"
          Request.encoding
          (function Request r -> Some r | _ -> None)
          (fun r -> Request r) ;
        case (Tag 2)
          ~title:"Terminated"
          Data_encoding.empty
          (function Terminated  -> Some () | _ -> None)
          (fun () -> Terminated) ;
        case (Tag 3)
          ~title:"Timeout"
          Data_encoding.empty
          (function Timeout  -> Some () | _ -> None)
          (fun () -> Timeout) ;
        case (Tag 4)
          ~title:"Crashed"
          (list error_encoding)
          (function Crashed errs -> Some errs | _ -> None)
          (fun errs -> Crashed errs) ;
        case (Tag 5)
          ~title:"Started"
          (option string)
          (function Started n -> Some n | _ -> None)
          (fun n -> Started n) ;
        case (Tag 6)
          ~title:"Triggering_shutdown"
          Data_encoding.empty
          (function Triggering_shutdown  -> Some () | _ -> None)
          (fun () -> Triggering_shutdown) ;
        case (Tag 7)
          ~title:"Duplicate"
          string
          (function Duplicate n -> Some n | _ -> None)
          (fun n -> Duplicate n) ;
      ]

  let pp base_name ppf = function
    | WorkerEvent evt ->
        Format.fprintf ppf "%a"
          Event.pp evt
    | Request req ->
        Format.fprintf ppf
          "@[<v 2>Request:@,%a@]"
          Request.pp req
    | Terminated ->
        Format.fprintf ppf  "@[Worker terminated [%s] @]"
          base_name
    | Timeout ->
        Format.fprintf ppf
          "@[Worker terminated with timeout [%s] @]"
          base_name
    | Crashed errs ->
        Format.fprintf ppf
          "@[<v 0>Worker crashed [%s]:@,%a@]"
          base_name
          (Format.pp_print_list Error_monad.pp) errs
    | Started None ->
        Format.fprintf ppf "Worker started"
    | Started (Some n) ->
        Format.fprintf ppf "Worker started for %s" n
    | Triggering_shutdown ->
        Format.fprintf ppf "Triggering shutdown"
    | Duplicate name ->
        let full_name =
          if name = "" then base_name else Format.asprintf "%s_%s" base_name name in
        Format.fprintf ppf "Worker.launch: duplicate worker %s" full_name

  module MakeDefinition (Static : sig val worker_name : string end) :
    Internal_event.EVENT_DEFINITION with type t = t=  struct
    let name = Static.worker_name
    type nonrec t = t
    let encoding =
      let open Data_encoding in
      let v0_encoding =  status_encoding in
      With_version.(encoding ~name (first_version v0_encoding))
    let pp ppf (status: t)  =
      Format.fprintf ppf "%s : %a"
        name
        (Time.System.pp_stamped (pp Static.worker_name)) status
    let doc = "Worker status."
    let level (status : t)  =
      match status.data with
      | WorkerEvent evt ->
          Event.level evt
      | Request _ -> Internal_event.Debug
      | Terminated
      | Timeout
      | Started _ -> Internal_event.Notice
      | Crashed _ -> Internal_event.Error
      | Triggering_shutdown -> Internal_event.Debug
      | Duplicate _ -> Internal_event.Error
  end
end

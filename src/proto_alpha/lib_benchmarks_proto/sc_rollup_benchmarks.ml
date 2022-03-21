(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Trili Tech, <contact@trili.com>                        *)
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

open Protocol

(** A benchmark for estimating the gas cost of {!Sc_rollup.Inbox.add_messages}.
    We assume that the cost (in gas) `cost(n)` of adding a message of size [n] 
    bytes to the inbox satisfies the equation `cost(n) = c_0 + c_1 * n`, where 
    `c_0` and `c_1` are the values to be benchmarked. We also assume that the 
    cost of adding messages `m_0, ..., m_k` to a rollup inbox is 
    `\sum_{i=0}^{k} cost(|m_i|)`. Thus, it suffices to estimate the cost of 
    adding a single message to the inbox.
*)

module Sc_rollup_add_messages_benchmark : Benchmark.S = struct
  let name = "Sc_rollup_inbox_add_message"

  let info = "Estimating the costs of adding a single message to a rollup inbox"

  let tags = ["scoru"]

  type config = {max_length : int}

  let config_encoding =
    let open Data_encoding in
    conv
      (fun {max_length} -> max_length)
      (fun max_length -> {max_length})
      (obj1 (req "max_bytes" int31))

  let default_config = {max_length = 1 lsl 16}

  type workload = {message_length : int}

  let workload_encoding =
    let open Data_encoding in
    conv
      (fun {message_length} -> message_length)
      (fun message_length -> {message_length})
      (obj1 (req "message_length" int31))

  let workload_to_vector {message_length} =
    Sparse_vec.String.of_list [("message_length", float_of_int message_length)]

  let add_message_model =
    Model.make
      ~conv:(fun {message_length} -> (message_length, ()))
      ~model:
        (Model.affine
           ~intercept:(Free_variable.of_string "cost_add_message_base")
           ~coeff:(Free_variable.of_string "cost_add_message_per_byte"))

  let models = [("add_message", add_message_model)]

  let benchmark rng_state conf () =
    let message =
      Base_samplers.string rng_state ~size:{min = 1; max = conf.max_length}
    in
    let message_length = String.length message in
    let level = Raw_level_repr.of_int32_exn Int32.zero in
    let rollup = Sc_rollup_repr.Address.zero in
    let history =
      Sc_rollup_inbox_repr.history_at_genesis ~bound:(Int64.of_int 1_000_000)
    in

    let empty_inbox = Sc_rollup_inbox_repr.empty rollup level in
    let ctxt =
      match
        Lwt_main.run
          ( Context.init1 () >>=? fun (block, _) ->
            Incremental.begin_construction block >|=? fun b ->
            Alpha_context.Internal_for_tests.to_raw (Incremental.alpha_ctxt b)
          )
      with
      | Ok context -> context
      | _ -> assert false
    in
    let empty_messages =
      Raw_context.Sc_rollup_in_memory_inbox.current_messages ctxt rollup
    in
    let workload = {message_length} in
    let closure () =
      ignore
        (Sc_rollup_inbox_repr.add_messages
           history
           empty_inbox
           level
           [message]
           empty_messages)
    in
    Generator.Plain {workload; closure}

  let create_benchmarks ~rng_state ~bench_num config =
    List.repeat bench_num (benchmark rng_state config)

  let () =
    Registration.register_for_codegen name (Model.For_codegen add_message_model)
end

let () = Registration.register (module Sc_rollup_add_messages_benchmark)

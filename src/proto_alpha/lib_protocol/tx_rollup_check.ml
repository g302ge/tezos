(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2022 Oxhead Alpha <info@oxhead-alpha.com>                   *)
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

(* FIXME: register this *)
type error += Tx_rollup_inbox_size_exceeded

(* FIXME: register this *)
type error += Tx_rollup_inbox_progress_limit

open Alpha_context

let check_inbox_size ctxt metadata =
  let Constants.{tx_rollup_hard_size_limit_per_inbox; _} =
    Constants.parametric ctxt
  in
  error_unless
    Compare.Int.(
      metadata.Tx_rollup_inbox.Metadata.cumulated_size
      <= tx_rollup_hard_size_limit_per_inbox)
    Tx_rollup_inbox_size_exceeded

let check_inbox_progress_limit ctxt state =
  let Constants.{tx_rollup_max_unfinalized_levels; _} =
    Constants.parametric ctxt
  in
  let unfinalized_level_count = Tx_rollup_state.unfinalized_level_count state in
  error_unless
    Compare.Int.(unfinalized_level_count <= tx_rollup_max_unfinalized_levels)
    Tx_rollup_inbox_progress_limit

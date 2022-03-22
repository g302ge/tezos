(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs. <contact@nomadic-labs.com>               *)
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

(** [assert] contains Alcotest convenience assertions. *)

(** Alcotest check that [b] is [true]. *)
let assert_true str b = Alcotest.check Alcotest.bool str true b

(** Alcotest check that [b] is [false]. *)
let assert_false str b = Alcotest.check Alcotest.bool str false b

(** Alcotest version of [assert false]. *)
let impossible str = assert_true str false

(** Assert that at least one value in [l] satisfies [f]. *)
let check_any ?(msg = "No value in the list satifies the condition.") f l =
  if not (List.exists f l) then Alcotest.fail msg

(** [contains m msg x ls] asserts that one testable in [ls] equals
    [x], and otherwise fails with [msg] *)
let contains (type a) (m : a Alcotest.testable) msg (x : a) (ls : a list) : unit
    =
  let (module M) = m in
  let (module L) = Alcotest.list m in
  if not @@ List.exists (M.equal x) ls then
    Alcotest.failf "%s. Could not find %a in %a" msg M.pp x L.pp ls

let fail expected given msg =
  Format.kasprintf
    Stdlib.failwith
    "@[%s@ expected: %s@ got: %s@]"
    msg
    expected
    given

let fail_msg fmt = Format.kasprintf (fail "" "") fmt

let default_printer _ = ""

let equal ?(eq = ( = )) ?(prn = default_printer) ?(msg = "") x y =
  if not (eq x y) then fail (prn x) (prn y) msg

let equal_bytes ?msg s1 s2 = equal ?msg ~prn:(fun s -> Bytes.to_string s) s1 s2

let equal_bytes_option ?msg o1 o2 =
  let prn = function None -> "None" | Some s -> Bytes.to_string s in
  equal ?msg ~prn o1 o2

let equal_bool ?msg b1 b2 = equal ?msg ~prn:(fun s -> string_of_bool s) b1 b2

let equal_string_option ?msg o1 o2 =
  let prn = function None -> "None" | Some s -> s in
  equal ?msg ~prn o1 o2

let is_none ?(msg = "") x = if x <> None then fail "None" "Some _" msg

let make_equal_list eq prn ?(msg = "") x y =
  let to_string l =
    Printf.sprintf "[%s]" (String.concat "; " (List.map prn l))
  in
  let rec iter i x y =
    match (x, y) with
    | (hd_x :: tl_x, hd_y :: tl_y) ->
        if eq hd_x hd_y then iter (succ i) tl_x tl_y
        else
          let fm = Printf.sprintf "%s (at index %d)" msg i in
          fail (prn hd_x) (prn hd_y) fm
    | (_ :: _, []) | ([], _ :: _) ->
        let fm =
          Printf.sprintf
            "%s (lists of different sizes: %d <> %d, the lists being %s and %s)"
            msg
            (List.length x)
            (List.length y)
            (to_string x)
            (to_string y)
        in
        fail_msg "%s" fm
    | ([], []) -> ()
  in
  iter 0 x y

let equal_string_list = make_equal_list String.equal Fun.id

let equal_string_list_list ?msg l1 l2 =
  let pr_persist l =
    let res = String.concat ";" (List.map (fun s -> Printf.sprintf "%S" s) l) in
    Printf.sprintf "[%s]" res
  in
  make_equal_list ?msg ( = ) pr_persist l1 l2

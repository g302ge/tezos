(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

type counter = int
let counter = Data_encoding.int31

(* Distributed DB peer metadata *)
type messages =
  {
    mutable branch: counter ;
    mutable head: counter ;
    mutable block_header: counter ;
    mutable operations: counter ;
    mutable protocols: counter ;
    mutable operation_hashes_for_block: counter ;
    mutable operations_for_block: counter ;
    mutable other: counter ;
  }

let sent_requests_encoding =
  let open Data_encoding in
  (conv
     (fun { branch ; head ; block_header ;
            operations ; protocols ;
            operation_hashes_for_block ;
            operations_for_block ;
            other ; } -> (branch, head, block_header,
                          operations, protocols,
                          operation_hashes_for_block,
                          operations_for_block,
                          other ))
     (fun (branch, head, block_header,
           operations, protocols,
           operation_hashes_for_block,
           operations_for_block,
           other) -> { branch ; head ; block_header ;
                       operations ; protocols ;
                       operation_hashes_for_block ;
                       operations_for_block ;
                       other })
  )
    (obj8
       (req "branch" counter)
       (req "head" counter)
       (req "block_header" counter)
       (req "operations" counter)
       (req "protocols" counter)
       (req "operation_hashes_for_block" counter)
       (req "operations_for_block" counter)
       (req "other" counter)
    )

type requests_kind =
  | Branch | Head | Block_header | Operations
  | Protocols | Operation_hashes_for_block
  | Operations_for_block | Other


type requests = {
  sent : messages ;
  (** p2p sent messages of type requests *)
  received : messages ;
  (** p2p received messages of type requests *)
  failed : messages ;
  (** p2p messages of type requests that we failed to send *)
  scheduled : messages ;
  (** p2p messages ent via request scheduler *)
}

let requests_encoding =
  let open Data_encoding in
  (conv
     (fun
       { sent ; received ;
         failed ; scheduled } -> (sent, received,
                                  failed, scheduled))
     (fun (sent, received,
           failed, scheduled) -> { sent ; received ;
                                   failed ; scheduled })
  )
    (obj4
       (req "sent" sent_requests_encoding)
       (req "received" sent_requests_encoding)
       (req "failed" sent_requests_encoding)
       (req "scheduled" sent_requests_encoding)
    )


(* Prevalidator peer metadata *)
type prevalidator_results =
  { cannot_download : counter ; cannot_parse : counter ;
    refused_by_prefilter : counter ;
    refused_by_postfilter : counter ;
    (* prevalidation results *)
    applied : counter ; branch_delayed : counter ;
    branch_refused : counter ;
    refused : counter ; duplicate : counter ; outdated : counter }

let prevalidator_results_encoding =
  let open Data_encoding in
  (conv
     (fun { cannot_download ;
            cannot_parse ;
            refused_by_prefilter ;
            refused_by_postfilter ;
            applied ; branch_delayed;
            branch_refused ;
            refused ; duplicate ;
            outdated } -> (cannot_download, cannot_parse,
                           refused_by_prefilter,
                           refused_by_postfilter,
                           applied, branch_delayed,
                           branch_refused,
                           refused, duplicate, outdated))
     (fun (cannot_download,
           cannot_parse,
           refused_by_prefilter,
           refused_by_postfilter,
           applied, branch_delayed,
           branch_refused,
           refused, duplicate,
           outdated) -> { cannot_download ; cannot_parse ;
                          refused_by_prefilter ;
                          refused_by_postfilter ;
                          applied ; branch_delayed;
                          branch_refused ;
                          refused ; duplicate ; outdated }

     )
     (obj10
        (req "cannot_download" counter)
        (req "cannot_parse" counter)
        (req "refused_by_prefilter" counter)
        (req "refused_by_postfilter" counter)
        (req "applied" counter)
        (req "branch_delayed" counter)
        (req "branch_refused" counter)
        (req "refused" counter)
        (req "duplicate" counter)
        (req "outdated" counter)
     )
  )


type resource_kind =
  | Block | Operations | Protocol

type advertisement = Head | Branch

type metadata =
  (* Distributed_db *)
  | Received_request of requests_kind
  | Sent_request of requests_kind
  | Failed_request of requests_kind
  | Scheduled_request of requests_kind
  | Received_response of requests_kind
  | Sent_response of requests_kind
  | Unexpected_response
  | Unactivated_chain
  | Inactive_chain
  | Future_block
  | Unadvertised of resource_kind
  | Sent_advertisement of advertisement
  | Received_advertisement of advertisement
  | Outdated_response (* TODO : unused *)
  (* Peer validator *)
  | Valid_blocks | Old_heads
  (* Prevalidation *)
  | Cannot_download | Cannot_parse
  | Refused_by_prefilter
  | Refused_by_postfilter
  | Applied | Branch_delayed
  | Branch_refused
  | Refused | Duplicate | Outdated




type responses = {
  mutable sent : messages ;
  (** p2p sent messages of type responses *)
  mutable failed : messages ;
  (** p2p sent messages of type responses *)
  mutable received : messages ;
  (** p2p received responses *)
  mutable unexpected : counter ;
  (** p2p received responses that were unexpected *)
  mutable outdated : counter ;
  (** p2p received responses that are now outdated *)
}


let responses_encoding =
  let open Data_encoding in
  (conv
     (fun
       { sent ; failed ; received ;
         unexpected ; outdated ; } -> (sent, failed, received,
                                       unexpected, outdated))
     (fun
       (sent, failed, received,
        unexpected, outdated) -> { sent ; failed ; received ;
                                   unexpected ; outdated })
  )
    (obj5
       (req "sent" sent_requests_encoding)
       (req "failed" sent_requests_encoding)
       (req "received" sent_requests_encoding)
       (req "unexpected" counter)
       (req "outdated" counter)
    )


type unadvertised = {
  mutable block : counter ;
  (** requests for unadvertised block *)
  mutable operations : counter ;
  (** requests for unadvertised operations *)
  mutable protocol : counter ;
  (** requests for unadvertised protocol *)
}

let unadvertised_encoding =
  let open Data_encoding in
  (conv
     (fun
       { block ; operations ; protocol ; } -> (block, operations, protocol))
     (fun
       (block, operations, protocol) -> { block ; operations ; protocol ; })
  )
    (obj3
       (req "block" counter)
       (req "operations" counter)
       (req "protocol" counter)
    )


type advertisements_kind = {
  mutable head : counter ;
  mutable branch : counter ;
}

let advertisements_kind_encoding =
  let open Data_encoding in
  (conv
     (fun
       { head ; branch ; } -> (head, branch))
     (fun
       (head, branch) -> { head ; branch ; })
  )
    (obj2
       (req "head" counter)
       (req "branch" counter)
    )

type advertisements = {
  mutable sent: advertisements_kind ;
  mutable received: advertisements_kind ;
}


let advertisements_encoding =
  let open Data_encoding in
  (conv
     (fun
       { sent ; received ; } -> (sent, received))
     (fun
       (sent, received) -> { sent ; received ; })
  )
    (obj2
       (req "sent" advertisements_kind_encoding)
       (req "received" advertisements_kind_encoding)
    )

type t = {
  mutable responses : responses ;
  (** responses sent/received *)
  mutable requests : requests ;
  (** requests sent/received  *)
  mutable valid_blocks : counter ;
  (** new valid blocks advertized by a peer *)
  mutable old_heads : counter ;
  (** previously validated blocks from a peer *)
  mutable prevalidator_results : prevalidator_results ;
  (** prevalidator metadata *)
  mutable unactivated_chains : counter ;
  (** requests from unactivated chains *)
  mutable inactive_chains : counter ;
  (** advertise inactive chains *)
  mutable future_blocks_advertised : counter ;
  (** future blocks *)
  mutable unadvertised : unadvertised ;
  (** requests for unadvertised resources *)
  mutable advertisements : advertisements ;
  (** advertisements sent *)
}

let empty () =
  let empty_request () =
    { branch = 0 ; head = 0 ; block_header = 0 ;
      operations = 0 ; protocols = 0 ;
      operation_hashes_for_block = 0 ;
      operations_for_block = 0 ;
      other = 0 ;
    } in
  {
    responses = { sent = empty_request () ;
                  failed = empty_request () ;
                  received = empty_request () ;
                  unexpected = 0 ;
                  outdated = 0 ;
                } ;
    requests =
      { sent = empty_request () ;
        failed = empty_request () ;
        scheduled = empty_request () ;
        received = empty_request () ;
      } ;
    valid_blocks = 0 ;
    old_heads = 0 ;
    prevalidator_results =
      { cannot_download = 0 ; cannot_parse = 0 ;
        refused_by_prefilter = 0 ; refused_by_postfilter = 0 ;
        applied  = 0 ; branch_delayed = 0 ; branch_refused = 0 ;
        refused = 0 ; duplicate = 0 ; outdated = 0
      } ;
    unactivated_chains = 0 ;
    inactive_chains = 0 ;
    future_blocks_advertised = 0 ;
    unadvertised = {block = 0 ; operations = 0 ; protocol = 0 } ;
    advertisements = { sent = { head = 0 ; branch = 0 ; } ;
                       received = { head = 0 ; branch = 0 ; } }
  }


let encoding =
  let open Data_encoding in
  (conv
     (fun { responses ; requests ;
            valid_blocks ; old_heads ;
            prevalidator_results ;
            unactivated_chains ;
            inactive_chains ;
            future_blocks_advertised ;
            unadvertised ;
            advertisements } ->
       ((responses, requests,
         valid_blocks, old_heads,
         prevalidator_results,
         unactivated_chains,
         inactive_chains,
         future_blocks_advertised),
        (unadvertised,
         advertisements))
     )
     (fun ((responses, requests,
            valid_blocks, old_heads,
            prevalidator_results,
            unactivated_chains,
            inactive_chains,
            future_blocks_advertised),
           (unadvertised,
            advertisements)) ->
       { responses ; requests ;
         valid_blocks ; old_heads ;
         prevalidator_results ;
         unactivated_chains ;
         inactive_chains ;
         future_blocks_advertised ;
         unadvertised ;
         advertisements ; }
     )
  )
    (merge_objs
       (obj8
          (req "responses" responses_encoding)
          (req "requests" requests_encoding)
          (req "valid_blocks" counter)
          (req "old_heads" counter)
          (req "prevalidator_results" prevalidator_results_encoding)
          (req "unactivated_chains" counter)
          (req "inactive_chains" counter)
          (req "future_blocks_advertised" counter)

       )
       (obj2
          (req "unadvertised" unadvertised_encoding)
          (req "advertisements" advertisements_encoding)
       )
    )

let incr_requests (msgs : messages) (req : requests_kind) =
  match req with
  | Branch -> msgs.branch <- msgs.branch + 1
  | Head -> msgs.head <- msgs.head + 1
  | Block_header -> msgs.block_header <- msgs.block_header + 1
  | Operations -> msgs.operations <- msgs.operations + 1
  | Protocols -> msgs.protocols <- msgs.protocols + 1
  | Operation_hashes_for_block ->
      msgs.operation_hashes_for_block <- msgs.operation_hashes_for_block + 1
  | Operations_for_block ->
      msgs.operations_for_block <- msgs.operations_for_block + 1
  | Other ->
      msgs.other <- msgs.other + 1



let incr_unadvertised { unadvertised = u ; _ } = function
  | Block -> u.block <- u.block + 1
  | Operations -> u.operations <- u.operations + 1
  | Protocol -> u.protocol <- u.protocol + 1


let incr ({responses = rsps ; requests = rqst ; _ } as m) metadata =
  match metadata with
  (* requests *)
  | Received_request req ->
      incr_requests rqst.received req
  | Sent_request req ->
      incr_requests rqst.sent req
  | Scheduled_request req ->
      incr_requests rqst.scheduled req
  | Failed_request req ->
      incr_requests rqst.failed req
  (* responses *)
  | Received_response req ->
      incr_requests rsps.received req
  | Sent_response req ->
      incr_requests rsps.sent req
  | Unexpected_response ->
      rsps.unexpected <- rsps.unexpected + 1
  | Outdated_response ->
      rsps.outdated <- rsps.outdated + 1
  (* Advertisements *)
  | Sent_advertisement ad ->
      begin match ad with
        | Head ->
            m.advertisements.sent.head <- m.advertisements.sent.head + 1
        | Branch ->
            m.advertisements.sent.branch <- m.advertisements.sent.branch + 1
      end
  | Received_advertisement ad ->
      begin match ad with
        | Head ->
            m.advertisements.received.head <- m.advertisements.received.head + 1
        | Branch ->
            m.advertisements.received.branch <- m.advertisements.received.branch + 1
      end
  (* Unexpected erroneous msg *)
  | Unactivated_chain ->
      m.unactivated_chains <- m.unactivated_chains + 1
  | Inactive_chain ->
      m.inactive_chains <- m.inactive_chains + 1
  | Future_block ->
      m.future_blocks_advertised <- m.future_blocks_advertised + 1
  | Unadvertised u -> incr_unadvertised m u
  (* Peer validator *)
  | Valid_blocks ->
      m.valid_blocks <- m.valid_blocks + 1
  | Old_heads ->
      m.old_heads <- m.old_heads + 1
  (* prevalidation *)
  | Cannot_download ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          cannot_download = m.prevalidator_results.cannot_download + 1 }
  | Cannot_parse -> m.prevalidator_results <-
        { m.prevalidator_results with
          cannot_parse = m.prevalidator_results.cannot_parse + 1 }
  | Refused_by_prefilter -> m.prevalidator_results <-
        { m.prevalidator_results with
          refused_by_prefilter =
            m.prevalidator_results.refused_by_prefilter + 1 }
  | Refused_by_postfilter -> m.prevalidator_results <-
        { m.prevalidator_results with
          refused_by_postfilter =
            m.prevalidator_results.refused_by_postfilter + 1 }
  | Applied ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          applied = m.prevalidator_results.applied + 1 }
  | Branch_delayed ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          branch_delayed = m.prevalidator_results.branch_delayed + 1 }
  | Branch_refused ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          branch_refused = m.prevalidator_results.branch_refused + 1 }
  | Refused ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          refused = m.prevalidator_results.refused + 1 }
  | Duplicate ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          duplicate = m.prevalidator_results.duplicate + 1 }
  | Outdated ->
      m.prevalidator_results <-
        { m.prevalidator_results with
          outdated = m.prevalidator_results.outdated + 1 }


(* shortcuts to update sent/failed requests/responses *)
let update_requests { requests = { sent ; failed ; _  } ; _ } kind = function
  | true -> incr_requests sent kind
  | false -> incr_requests failed kind

let update_responses { responses = { sent ; failed ; _ } ; _ } kind = function
  | true -> incr_requests sent kind
  | false -> incr_requests failed kind


(* Scores computation *)
(* TODO:
   - scores cannot be kept as integers (use big numbers?)
   - they scores should probably be reset frequently (at each block/cycle?)
   - we might still need to keep some kind of score history
       - store only best/worst/last_value/mean/variance... ?
   - do we need to keep "good" scores ?
        - maybe "bad" scores are enough to reduce resources
          allocated to misbehaving peers *)
let distributed_db_score _ =
  (* TODO *)
  1.0

let prevalidation_score { prevalidator_results = _ ; _ }  =
  (* TODO *)
  1.0

let score _ =
  (* TODO *)
  1.0

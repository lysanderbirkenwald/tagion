module tagion.Keywords;

private import tagion.Base : EnumText;

// Keyword list for the BSON packages
enum _keywords = [
    "pubkey",       // Pubkey
    "signature",        // signature of the block
    "altitude",   // altitude
    "received_order",
    "tidewave",
    "wavefront",  // Wave front is the list of events hashs
    "ebody",      // Event body
    "event",      // Event including the eventbody

    "message",
    "mother",
    "father",
    "daughter",
    "son",
    "payload",
    "channel",
    "witness",
    "witness_mask",
    "round_mask",
    "round_seen",
    "round_received",
    "coin",
    "decided",
    "decided_count",
//    "total",
//    "decided_mask",
    "famous",
    "famous_votes",
    "round",
    "number",
    "remove",
    "forked",
    "strongly_seeing",
    "strong_votes",
    "strong_mask",
    "iterations",
    "altenative",
    "looked_at_mask",
    "looked_at_count",
    "seeing_completed",
    "completed",
    "epoch",
    "list",
    "time",
    "events",     // List of event
    "type",       // Package type
    "block",     // block

    "rim",
    "buckets",
    "tab",
    "transaction_id",
    "result_code",
    "error_code",
    "output",
    "signatures",
    "signatur",
    "transaction_object",
    "transaction_scripting_object",
    "payers",
    "payees",
    "input_bills",
    "output_bills",
    "bill",
    "bill_number",
    "bill_body",
    "bill_type",
    "value",
    "ownerkey",
    // Scripting
    "code",
    "source",

    // DART
//    "fingerprint",
//    "branch",
    "indices",
    "fingerprint",
    "fingerprints",
    "rims",
    "stub"
    ];

// Generated the Keywords and enum string list
mixin(EnumText!("Keywords", _keywords));

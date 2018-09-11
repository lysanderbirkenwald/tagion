module tagion.Keywords;

private import tagion.Base : EnumText;

// Keyword list for the BSON packages
enum _keywords = [
    "pubkey",       // Pubkey
    "signature",        // signature of the block
    "altitude",   // altitude
    "tidewave",
    "wavefront",  // Wave front is the list of events hashs
    "ebody",      // Event body
    "event",      // Event including the eventbody
    "message",
    "mother",
    "father",
    "payload",
    "channel",
    "witness",
    "witness_mask",
    "round_mask",
    "famous",
    "famous_votes",
    "round",
    "forked",
    "strongly_seeing",
    "strong_votes",
    "iterations",
//        "events",     // List of event
    "type",       // Package type
    "block"     // block
    ];

// Generated the Keywords and enum string list
mixin(EnumText!("Keywords", _keywords));

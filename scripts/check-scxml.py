#!/usr/bin/env python3
"""Independent checker for keiki's descriptive SCXML export.

Usage: check-scxml.py DIR

DIR must contain exactly the fixture documents written by the keiki test
executable (see scripts/check-scxml.sh). Every document is parsed with the
standard-library XML parser, its metadata comments are decoded with the
standard-library JSON decoder, and the result is checked against the
documented export subset (docs/guide/scxml-export.md) and against each
fixture's expected graph and descriptions. Finally the checker verifies that
it rejects deliberately broken variants of a good document.

This validates keiki's export contract only. It is not a general SCXML
conformance checker and says nothing about third-party tools.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://www.w3.org/2005/07/scxml"
MARKER = "keiki-scxml-v1 "
EVENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
XML_DECL = b'<?xml version="1.0" encoding="UTF-8"?>\n'

DOCUMENT_KEYS = [
    "kind",
    "purpose",
    "edgeView",
    "includeBehavior",
    "warning",
    "replayEdges",
    "edgeIndex",
    "updateSemantics",
]
STATE_KEYS = ["kind", "id", "index", "label", "accepting"]
EDGE_KEYS = [
    "kind",
    "source",
    "target",
    "edgeIndex",
    "mode",
    "displayed",
    "event",
    "eventSource",
]
REPLAY_KEYS = ["note"]
BEHAVIOR_KEYS = ["guard", "update", "assignments", "updateReads", "outputs"]


class CheckError(Exception):
    pass


def require(cond, message):
    if not cond:
        raise CheckError(message)


def q(tag):
    return "{%s}%s" % (NS, tag)


def blank(text):
    return text is None or text.strip() == ""


def is_comment(node):
    return node.tag is ET.Comment


def decode_record(node, where):
    require(is_comment(node), f"{where}: expected a metadata comment")
    text = node.text or ""
    require(text.startswith(MARKER), f"{where}: comment lacks {MARKER!r} marker")
    try:
        record = json.loads(text[len(MARKER):])
    except json.JSONDecodeError as err:
        raise CheckError(f"{where}: metadata is not JSON: {err}") from err
    require(isinstance(record, dict), f"{where}: metadata is not a JSON object")
    return record


class Edge:
    def __init__(self, record, drawn, event, target):
        self.record = record
        self.drawn = drawn
        self.event = event
        self.target = target


class State:
    def __init__(self, element, sid, record):
        self.element = element
        self.id = sid
        self.record = record
        self.edges = []

    @property
    def transitions(self):
        return [e for e in self.edges if e.drawn]


class Chart:
    def __init__(self, initial, document, states):
        self.initial = initial
        self.document = document
        self.states = states
        self.by_id = {s.id: s for s in states}

    def state(self, label):
        matches = [s for s in self.states if s.record["label"] == label]
        require(len(matches) == 1, f"expected one state labelled {label!r}")
        return matches[0]


def parse_chart(data, name):
    """Parse and structurally validate one document; return its Chart."""
    require(data.startswith(XML_DECL), f"{name}: missing UTF-8 XML declaration")
    require(data.endswith(b"\n"), f"{name}: missing trailing newline")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as err:
        raise CheckError(f"{name}: not UTF-8: {err}") from err
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    try:
        parser.feed(data)
        root = parser.close()
    except ET.ParseError as err:
        raise CheckError(f"{name}: XML parse error: {err}") from err

    require(root.tag == q("scxml"), f"{name}: root is {root.tag}, not scxml")
    require(
        set(root.attrib) == {"version", "datamodel", "initial"},
        f"{name}: unexpected root attributes {sorted(root.attrib)}",
    )
    require(root.get("version") == "1.0", f"{name}: version is not 1.0")
    require(root.get("datamodel") == "null", f"{name}: datamodel is not null")
    require(blank(root.text), f"{name}: text directly inside scxml")

    children = list(root)
    require(children, f"{name}: empty document")
    document = decode_record(children[0], f"{name}: document record")
    check_keys(document, DOCUMENT_KEYS, [], f"{name}: document record")
    require(document["kind"] == "document", f"{name}: first record is not a document")
    require(document["purpose"] == "descriptive-only", f"{name}: purpose")
    require(
        document["edgeView"] in ("forward-edges", "all-declared-edges"),
        f"{name}: unknown edgeView",
    )
    require(isinstance(document["includeBehavior"], bool), f"{name}: includeBehavior")
    require("not an executable" in document["warning"], f"{name}: warning text")

    states = []
    for position, element in enumerate(children[1:]):
        states.append(parse_state(element, position, document, name))
    require(states, f"{name}: no states")

    ids = [s.id for s in states]
    require(len(set(ids)) == len(ids), f"{name}: duplicate state IDs")
    chart = Chart(root.get("initial"), document, states)
    require(chart.initial in chart.by_id, f"{name}: initial does not resolve")
    for state in states:
        for edge in state.edges:
            require(
                edge.record["target"] in chart.by_id,
                f"{name}: edge {state.id}/{edge.record['edgeIndex']} target "
                f"{edge.record['target']!r} does not resolve",
            )
    return chart


def check_keys(record, required, optional, where):
    keys = list(record)
    expected = [k for k in required + optional if k in record]
    require(
        keys == expected and all(k in record for k in required),
        f"{where}: keys {keys} do not match the schema {required} + {optional}",
    )


def parse_state(element, position, document, name):
    tag = element.tag
    require(
        tag in (q("state"), q("final")), f"{name}: unexpected element {tag}"
    )
    require(set(element.attrib) == {"id"}, f"{name}: state attributes")
    require(blank(element.text) and blank(element.tail), f"{name}: stray text")
    sid = element.get("id")
    require(
        re.fullmatch(r"s%d_[A-Za-z0-9_]*" % position, sid),
        f"{name}: state ID {sid!r} is not s{position}_<name>",
    )
    children = list(element)
    require(children, f"{name}: {sid} has no state record")
    record = decode_record(children[0], f"{name}: {sid} state record")
    check_keys(record, STATE_KEYS, [], f"{name}: {sid} state record")
    require(record["kind"] == "state", f"{name}: {sid} first record kind")
    require(record["id"] == sid, f"{name}: {sid} record id mismatch")
    require(record["index"] == position, f"{name}: {sid} index mismatch")
    require(isinstance(record["label"], str), f"{name}: {sid} label")
    require(isinstance(record["accepting"], bool), f"{name}: {sid} accepting")
    state = State("final" if tag == q("final") else "state", sid, record)

    for child in children[1:]:
        if is_comment(child):
            edge_record = decode_record(child, f"{name}: {sid} omitted edge")
            state.edges.append(Edge(edge_record, False, None, None))
        else:
            require(child.tag == q("transition"), f"{name}: {sid} child {child.tag}")
            require(
                set(child.attrib) == {"event", "target"},
                f"{name}: {sid} transition attributes {sorted(child.attrib)}",
            )
            require(blank(child.text) and blank(child.tail), f"{name}: stray text")
            inner = list(child)
            require(len(inner) == 1, f"{name}: {sid} transition needs one record")
            edge_record = decode_record(inner[0], f"{name}: {sid} edge record")
            state.edges.append(
                Edge(edge_record, True, child.get("event"), child.get("target"))
            )

    for expected_index, edge in enumerate(state.edges):
        check_edge(state, position, expected_index, edge, document, name)

    accepting = record["accepting"]
    if state.element == "final":
        require(accepting, f"{name}: {sid} is <final> but not accepting")
        require(not state.transitions, f"{name}: {sid} <final> has transitions")
    elif accepting:
        require(state.transitions, f"{name}: {sid} should be <final>")
    return state


def check_edge(state, position, expected_index, edge, document, name):
    r = edge.record
    where = f"{name}: {state.id} edge {expected_index}"
    replay = r.get("mode") == "ReplayOnly"
    behavior = document["includeBehavior"]
    check_keys(
        r,
        EDGE_KEYS,
        (REPLAY_KEYS if replay else []) + (BEHAVIOR_KEYS if behavior else []),
        where,
    )
    require(
        all(k in r for k in (REPLAY_KEYS if replay else [])), f"{where}: replay note"
    )
    require(
        all(k in r for k in (BEHAVIOR_KEYS if behavior else [])),
        f"{where}: missing behavioral data",
    )
    require(r["kind"] == "edge", f"{where}: kind")
    require(r["source"] == state.id, f"{where}: source")
    require(r["edgeIndex"] == expected_index, f"{where}: edgeIndex out of order")
    require(r["mode"] in ("Live", "ReplayOnly"), f"{where}: mode")
    require(r["displayed"] == edge.drawn, f"{where}: displayed flag")
    if document["edgeView"] == "forward-edges":
        require(edge.drawn == (r["mode"] == "Live"), f"{where}: forward view")
    else:
        require(edge.drawn, f"{where}: all-edges view omits an edge")
    event = r["event"]
    require(
        isinstance(event, str) and EVENT_RE.match(event), f"{where}: bad event label"
    )
    synthetic_live = f"keiki_edge_s{position}_e{expected_index}"
    synthetic_replay = f"keiki_replay_s{position}_e{expected_index}"
    if replay:
        require(event == synthetic_replay, f"{where}: replay label")
        require(r["eventSource"] == "synthetic", f"{where}: replay eventSource")
    elif r["eventSource"] == "synthetic":
        require(event == synthetic_live, f"{where}: synthetic label")
    else:
        require(r["eventSource"] == "input-constructor", f"{where}: eventSource")
        require(not event.startswith("keiki_"), f"{where}: reserved prefix")
    if edge.drawn:
        require(edge.event == event, f"{where}: event attribute != record")
        require(edge.target == r["target"], f"{where}: target attribute != record")
    if behavior:
        require(isinstance(r["guard"], str), f"{where}: guard")
        require(isinstance(r["update"], str), f"{where}: update")
        require(
            isinstance(r["assignments"], list)
            and all(isinstance(a, str) for a in r["assignments"]),
            f"{where}: assignments",
        )
        require(r["updateReads"] == "edge-entry-snapshot", f"{where}: updateReads")
        require(isinstance(r["outputs"], list), f"{where}: outputs")
        for out in r["outputs"]:
            require(
                isinstance(out, dict)
                and list(out) == ["constructor", "fields"]
                and isinstance(out["constructor"], str)
                and isinstance(out["fields"], list)
                and all(isinstance(f, str) for f in out["fields"]),
                f"{where}: output object",
            )


# --- Fixture expectations ---------------------------------------------------


def arrows(chart):
    return [(s.id, e) for s in chart.states for e in s.transitions]


def check_email_delivery(chart):
    require(len(chart.states) == 2, "email: expected two states")
    pending = chart.state("EmailPending")
    sent = chart.state("EmailSentVertex")
    require(chart.initial == pending.id, "email: initial is not pending")
    require(pending.element == "state", "email: pending element")
    require(sent.element == "final", "email: sent is not <final>")
    drawn = arrows(chart)
    require(len(drawn) == 1, "email: expected exactly one transition")
    source, edge = drawn[0]
    require(source == pending.id, "email: transition source")
    require(edge.event == "SendEmail", "email: transition event")
    require(edge.target == sent.id, "email: transition target")
    if chart.document["includeBehavior"]:
        r = edge.record
        require(r["guard"] == "SendEmail", "email: guard")
        require(
            r["assignments"]
            == [
                "emailSentAt := SendEmail.at",
                "emailSubject := SendEmail.subject",
                "emailRecipient := SendEmail.recipient",
            ],
            "email: assignments",
        )
        require(
            r["outputs"]
            == [
                {
                    "constructor": "EmailSent",
                    "fields": [
                        "SendEmail.recipient",
                        "SendEmail.subject",
                        "SendEmail.at",
                    ],
                }
            ],
            "email: outputs",
        )


EXPECTED = {
    "email-delivery.scxml": check_email_delivery,
}


# --- Negative self-test -----------------------------------------------------


def rejects(data, label):
    try:
        parse_chart(data, label)
    except CheckError:
        return True
    return False


def self_test(good):
    """The checker must reject broken variants of a known-good document."""
    text = good.decode("utf-8")
    broken = {
        "broken XML": good[: len(good) // 2],
        "missing target": text.replace(
            'target="s1_EmailSentVertex"', 'target="s9_Missing"', 1
        ).encode("utf-8"),
        "missing behavior": text.replace('"guard":"SendEmail",', "", 1).encode(
            "utf-8"
        ),
    }
    for label, data in broken.items():
        require(data != good, f"self-test: {label} mutation did not apply")
        require(rejects(data, label), f"self-test: checker accepted {label}")


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} DIR", file=sys.stderr)
        return 2
    directory = Path(argv[1])
    present = sorted(p.name for p in directory.iterdir() if p.is_file())
    expected = sorted(EXPECTED)
    try:
        require(
            present == expected,
            f"fixture set mismatch: expected {expected}, found {present}",
        )
        for name in expected:
            chart = parse_chart((directory / name).read_bytes(), name)
            EXPECTED[name](chart)
        self_test((directory / "email-delivery.scxml").read_bytes())
    except CheckError as err:
        print(f"SCXML check FAILED: {err}", file=sys.stderr)
        return 1
    print(
        f"SCXML fixtures: all {len(expected)} expected documents parsed; "
        "graph and metadata checks passed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

---
title: "Media over QUIC Relay Peering Protocol"
abbrev: moq-peering
docname: draft-evens-moq-peering-latest
date: {DATE}
category: std

ipr: trust200902
area:  "Web and Internet Transport"
submissionType: IETF
workgroup: "Media Over QUIC"
keyword:
 - media over quic
 - relay
 - peering

venue:
  group: "Media Over QUIC"
  type: "Working Group"
  mail: "moq@ietf.org"
  arch: "https://mailarchive.ietf.org/arch/browse/moq/"
  github: "TimEvens/draft-evens-moq-peering"
  latest: "https://timevens.github.io/draft-evens-moq-peering/draft-evens-moq-peering.html"

stand_alone: yes
smart_quotes: no
pi: [toc, sortrefs, symrefs, docmapping]

author:
  -
    ins: T. Evens
    name: Tim Evens
    organization: Cisco
    email: tievens@cisco.com

normative:
  QUIC: RFC9000
  QUIC-TLS: RFC9001
  TLS: RFC8446
  RFC8126: RFC8126
  MOQT: I-D.ietf-moq-transport
  CITYHASH:
    title: "CityHash, a family of hash functions"
    author:
      - ins: G. Pike
      - ins: J. Alakuijala
    date: 2011
    target: https://github.com/google/cityhash

--- abstract

This document defines the relay peering protocol used by Media over QUIC ({{MOQT}}) relays to exchange node, announce, and subscribe information and to forward objects between relays. Peering is split into control peering and data peering. Control peering stays established and carries the information bases. Data peering carries objects and MAY be pre-established or opened on demand. The two functions MAY share one QUIC session or use separate sessions. A peering session uses mutual TLS, together with an OPTIONAL token for authentication and authorization, before the peers exchange peering state.

--- middle

# Introduction

{{MOQT}} defines how a client publishes and subscribes to tracks at a relay. It leaves the relay-to-relay topology, the information a relay needs about other relays, and the encoding used to move objects between relays unspecified. A deployment that floods every announce and subscribe on the same path used for objects couples control-plane state to the data path and makes traffic engineering, fan-out, and policy enforcement difficult.

This document specifies how relays peer. Each relay keeps information bases that describe the nodes it can reach, the tracks that have been announced, and the subscribes that are active. Relays exchange those bases on control peering. They forward object bytes on data peering, using a subscriber node set to say which subscriber relays need the objects. Each hop chooses its own next hop from the node information base.

Control peering is always on for a peering relationship that exchanges information bases. Data peering MAY already be up, or a relay MAY open it when a forwarding path needs it. One QUIC connection can carry both, or the functions can use different connections. Several data connections MAY exist between the same pair of relays.

The QUIC handshake authenticates both endpoints with mutual TLS. An OPTIONAL token authenticates and authorizes the session as well, before the peers exchange information bases.

# Terminology

{::boilerplate bcp14-tagged}

The terms Client, Server, Publisher, Subscriber, Track, Track Namespace, and Object are imported from {{MOQT}}.

Node:
: A relay that participates in peering. A node has a Node ID, a node type, and a contact address.

Node ID:
: An unsigned 64-bit identifier that is unique among the nodes that exchange information bases.

Control peering:
: A peering function that exchanges information bases. It is kept established for the life of the peering relationship.

Data peering:
: A peering function that forwards objects. It MAY be established before there is anything to send, or opened when a path needs it.

Peering session:
: One QUIC connection between two nodes, used for control peering, data peering, or both.

Origin relay:
: The Edge node that holds the publisher, or the Edge parent of a Stub that holds the publisher. This document also calls it an o-relay.

Subscriber relay:
: The Edge node that holds the subscriber, or the Edge parent of a Stub that holds the subscriber. This document also calls it an s-relay.

Via relay:
: A node of type Via. This document also calls it a v-relay.

Subscriber node set (SNS):
: The set of subscriber-relay Node IDs that are to receive one flow of objects on a single data session, together with the session-local identifier for that set.

# Overview

Relays peer over {{QUIC}}. A session has one bidirectional stream for peering control messages. Object bytes use unidirectional streams and QUIC DATAGRAM frames. The application-layer protocol negotiation (ALPN) token is the ASCII string `moq-peering`.

Three session modes are negotiated in the first peering message:

| Value | Name    | What the session carries                                      |
|:------|:--------|:--------------------------------------------------------------|
| 0     | Control | Information bases. No object payloads.                        |
| 1     | Data    | Objects, plus the session-local subscriber node set.          |
| 2     | Both    | Information bases and objects on the same QUIC connection.    |
{: title="Peering session modes" }

Control peering uses mode Control or mode Both. Data peering uses mode Data or mode Both. A data session still has the bidirectional stream, because that stream carries the connect exchange and the subscriber node set for that session. A data session does not synchronize the information bases of other nodes.

## Relay Types {#node-types}

The node type is configured for the relay and is advertised with the node. A change of type requires the node to drop its peering sessions and reconnect so peers learn the new type.

| Value | Name | Behavior |
|:------|:-----|:---------|
| 0     | Via  | Forwards between relays. Does not accept {{MOQT}} clients. |
| 1     | Edge | Accepts {{MOQT}} clients and peers with Via, Edge, and Stub nodes. |
| 2     | Stub | Accepts local clients, dials one or more Edge parents, and does not accept inbound peering. |
{: title="Node types" }

### Via

A Via node is an aggregation and steering hop. It keeps the node information base so it can choose a next hop. It forwards objects from the subscriber node set on each data session. It does not need the full announce and subscribe tables in order to forward. When a Via sits on the control path, it stores and propagates announce and subscribe information so the information bases can reach Edge nodes that are not directly connected.

Via nodes are placed where many Edge nodes can share one fan-out. An Edge node uses a Via when a direct mesh would duplicate too much traffic, violate policy, or cross a poor network path.

### Edge

An Edge node accepts {{MOQT}} client sessions and peering sessions. It is the node that turns a client announce or subscribe into information-base state, and the node that turns received objects back into {{MOQT}} objects for local subscribers. It computes subscriber node sets for the data sessions it sends on.

An Edge node MAY sit behind a load balancer or an anycast address. The contact string advertised for the node is the name or address peers use to open a session, which MAY be the load balancer rather than an individual process.

### Stub

A Stub node is a lightweight child of one or more Edge parents. It dials those parents, uses session mode Both, and sends objects in both directions on the sessions it opened. That lets a Stub sit behind address translation or a firewall. A Stub does not accept inbound peering and is not installed in the node information base of any node other than its parents.

The parent Edge regenerates announce and subscribe state with its own Node ID as the source. Other relays see the parent, not the Stub. A Stub that has many local subscribers still produces one peering subscribe for a track at the parent. The parent is the s-relay and the o-relay for the rest of the network.

A client implementation MAY speak this protocol as a Stub instead of opening a {{MOQT}} session to an Edge. The Edge still presents that client to the rest of the network as its own.

## Relay Roles

Type and role are different. The type is configured. The role follows the clients attached to an Edge or to a Stub's parent.

* An origin relay is the Edge that receives a publish or announce from a publisher, or the Edge parent of the Stub that receives it.
* A subscriber relay is the Edge that receives a subscribe, or the Edge parent of the Stub that receives it.
* A Via node does not take either role. It forwards.

One Edge is an origin relay for some tracks and a subscriber relay for others at the same time.

## Topologies

Path selection prefers a direct session from the origin Edge to each subscriber Edge when policy, loss, delay, and fan-out allow it. This is a hub at the origin and a spoke to each subscriber relay.

~~~
Publisher --> Origin Edge --+--> Subscriber Edge --> Subscriber
                            |
                            +--> Subscriber Edge --> Subscriber
~~~
{: artwork-align="center" artwork-name="Direct edge-to-edge forwarding" }

When several subscriber Edges share a region, or when the direct path is not allowed, the origin Edge forwards to a Via. The Via splits the same objects toward the subscriber Edges. Further Via hops MAY be added to steer the network path. Via nodes can be added or removed for a track without resetting the publisher's {{MOQT}} session. An object stream already open on the previous hop drains there. A new stream and every datagram use the new hop.

~~~
Publisher --> Origin Edge --> Via --> Subscriber Edge --> Subscriber
                                |
                                +----> Subscriber Edge --> Subscriber
~~~
{: artwork-align="center" artwork-name="Forwarding through a Via" }

# Peering Sessions

## Control Peering

Control peering exchanges the node, announce, and subscribe information bases. It is always on. A node that participates in those bases keeps a control session up to each control peer for as long as that peering relationship exists. The control session does not follow the path objects take. A small set of control sessions, including a redundant session for availability, can serve many data sessions.

There is one control relationship between two nodes. If both nodes open a session in mode Control or mode Both, the session initiated by the node with the lower Node ID is the control session. The other endpoint closes the extra control session. Data sessions are not limited by this rule.

When a control session ends, each side removes node, announce, and subscribe state learned only through that session and selects paths again. Object state that belongs to a data session is removed when that data session ends.

The initiator of a session opens one bidirectional QUIC stream and sends every control message on it. CONNECT is the first message. The acceptor latches onto that stream and sends CONNECT_RESPONSE and later control messages on it. The initiator MAY open a replacement bidirectional stream. The acceptor adopts the new stream when a control message arrives on it and resets the previous control stream if that stream is still open. Two control streams are not in use at once.

## Data Peering

Data peering forwards object bytes. QUIC streams opened for objects are unidirectional and are opened by the sender. A session MAY carry objects in one direction or in both. Both directions are REQUIRED for a Stub, and for any node that MUST receive return traffic on a connection it opened because of address translation or a firewall. Additional data sessions between the same pair spread object streams across paths that the network can load-balance.

The bidirectional stream on a data session carries CONNECT, CONNECT_RESPONSE, and the subscriber node set for that session. It does not carry the shared information bases.

A subscriber node set is meaningful only on the session that will receive the objects. The sender allocates the set identifier. The receiver uses it to choose the next data sessions.

## Same Session or Separate Sessions

Mode Both puts control peering and data peering on one QUIC connection. The information bases and the subscriber node sets share that connection's control stream. Object bytes still use unidirectional streams and datagrams on that connection. A Stub uses this mode.

Mode Control and mode Data split the functions. The control session stays up and carries the information bases. Each data session is a separate QUIC connection. Object bytes and that session's subscriber node sets stay on the data connection. A node MAY have one control session and zero or more data sessions toward the same peer.

~~~
+-------------------+          +-------------------+
| Control session   |          | One session       |
| (always on)       |          | mode Both         |
| modes: Control    |          | bases and objects |
+-------------------+          +-------------------+
        |                               |
        +--> Data session (pre-set)     +--> objects and bases
        |
        +--> Data session (on demand)
~~~
{: artwork-align="center" artwork-name="Separate sessions and a combined session" }

## Pre-established and On-demand Data Peering

Data peering has two establishment styles.

* Pre-established. The data session is configured and connected before a subscriber needs it. Path selection can use it immediately. This is appropriate for Via hops and for Edge pairs that exchange objects continuously.
* On demand. The data session is opened when path selection needs a next hop that has no data session, and it MAY be closed when no subscriber node set still uses it. Control peering is not opened and closed this way.

An implementation MAY use either style, or both. Closing a data session does not withdraw information bases. Closing the control session does.

## What Each Session Exchanges

| Message family            | Control session | Data session | Mode Both |
|:--------------------------|:---------------:|:------------:|:---------:|
| CONNECT and response      | yes             | yes          | yes       |
| Node information base     | yes             | no           | yes       |
| Announce information base | yes             | no           | yes       |
| Subscribe information base| yes             | no           | yes       |
| Subscriber node set       | no              | yes          | yes       |
| Object payloads           | no              | yes          | yes       |
{: title="Messages by session function" }

CONNECT on every session carries the sender's own node information so the peer can identify the Node ID. That self description is not a dump of the node information base. The dump follows, on a control or both session, after a successful response.

# Information Bases

Information bases are the control-plane state. Nodes advertise entries and withdraw them. A relay also keeps a forwarding information base that it computes locally and does not advertise as a base of its own. The subscriber node set is session state used by data forwarding. It is specified with the bases because it names the subscriber relays that the bases imply.

| Base | Scope | Contents |
|:-----|:------|:---------|
| Node (NIB) | Control peers | Identity, location, cost, and path of each reachable node |
| Announce (AIB) | Control peers | Announced namespaces and tracks, with the origin node |
| Subscribe (SIB) | Control peers | Active subscribes, with the subscriber relay and its parameters |
| Forwarding (FIB) | Local | Next hop chosen for a node or for an object flow |
| Subscriber node set | One data session | Session-local id and the set of subscriber relays for one flow |
{: title="Information bases and related state" }

## Node Information Base

The node information base records how to reach other nodes. A node advertises itself with an empty path. A node that forwards an advertisement appends itself to the path. The receiver stores one candidate per peer that advertised a given Node ID and selects one of those candidates as the best next hop.

An advertisement is sent to a control peer only when all of the following are true:

* The peer's Node ID is not the Node ID being advertised.
* The peer's Node ID does not already appear in the path.
* The advertisement is new or is better than the candidate already stored from this session.

A withdrawal of a node is propagated when that advertisement was the last remaining way to reach the Node ID. While another session still reaches the node, the withdrawal is not forwarded. Receipt of a withdrawal removes the candidate learned from that session and runs path selection again.

Stub nodes are not inserted into the node information base beyond their parent.

### Node ID

Every node that appears in the node information base MUST be configured with a distinct Node ID. When two advertisements carry the same Node ID on different sessions, path selection keeps the better candidate. Operators assign the identifier. A deployment that hashes a host name or a device identifier to fill the 64-bit value MUST ensure the result does not collide inside the peering domain.

The textual form is `<high>:<low>`. The colon is REQUIRED. Each side is an unsigned 32-bit integer in decimal, or two unsigned 16-bit integers separated by a dot. The two styles MAY be mixed.

| Text | High | Low |
|:-----|-----:|----:|
| `1:1` | 1 | 1 |
| `1.2:1234` | 0x00010002 | 1234 |
| `100.2:9001.2001` | 0x00640002 | 0x232907D1 |
| `123456:789.100` | 123456 | 0x03150064 |
{: title="Node ID textual examples" }

The canonical display form is four decimal 16-bit fields, `high.high:low.low`. Implementations use the 64-bit value on the wire.

### Node Attributes

A node advertisement carries:

Id:
: The Node ID, as an unsigned 64-bit integer.

Type:
: The node type from {{node-types}}.

Contact:
: An octet string that tells a peer how to open a QUIC connection to this node. It is typically a DNS name or an address literal, and it MAY include a port. The contact MAY name a load balancer or an anycast address.

Longitude, Latitude:
: The node location in degrees, as binary64 values. Policy use of these values is deployment-specific.

Metric:
: An unsigned 64-bit cost. Lower sums are preferred. The default is 100. A peering session that is configured with a higher cost advertises that higher cost in place of the node metric on that session only.

Path:
: The ordered list of hops that forwarded this advertisement. Empty when the node advertises itself.

### Node Path

Each path item records the node that forwarded the advertisement, the smoothed round-trip time of the session on which that node received it, and the metric that node advertised on the session that carried the hop.

| Field | Size | Meaning |
|:------|-----:|:--------|
| Node ID | 8 | Node that appended this item |
| SRTT | 8 | Smoothed round-trip time, in microseconds, of the session the advertisement was received on |
| Metric | 8 | Metric advertised by that node on the session used for this hop |
{: title="Node path item" }

The path supports two decisions. A node refuses to forward an advertisement to a Node ID that is already listed, which stops loops. Path selection uses the length of the path, the sum of the metrics, and the sum of the smoothed round-trip times.

Sum of metrics is the advertised node metric plus the metric in every path item. A direct advertisement has an empty path, so its sum is the node metric alone. Sum of SRTT is the sum of the SRTT fields. A direct advertisement has sum zero.

## Announce Information Base

The announce information base records namespaces and tracks that publishers have announced. An Edge or Stub originates an entry when a local publisher announces. The source Node ID is the Edge that owns the publisher. A Stub's parent uses its own Node ID.

An entry is either a single track or a namespace that covers many tracks. Namespace entries omit the track name. Receivers index entries by the full-name hash and by successive namespace-tuple hashes so a later subscribe can find a matching announce.

Announce state is flooded on control peering, subject to policy. A relay MAY drop an announcement on input or on output. A subscriber relay uses the entries it keeps to answer a {{MOQT}} subscriber and to learn publisher parameters that were conveyed by the local {{MOQT}} stack. Relays that only forward peering messages use the hash and the source Node ID.

A withdrawal is sent when the publisher unannounces. The withdrawal is propagated on control peering the same way as the advertisement. Duplicate advertisements for the same source and full-name hash are not forwarded again.

## Subscribe Information Base

The subscribe information base records active subscribes. The subscriber relay originates an entry when it accepts a {{MOQT}} subscribe, or when its Stub child sends one. The source Node ID is that Edge. One entry represents the subscriber relay, not each local client. Many clients on one Edge collapse to one peering subscribe per track.

Each advertisement and withdrawal from the source node carries a 16-bit sequence number. The source node increments it by one for that subscribe, wrapping from 65535 to 0. Intermediate nodes forward the sequence unchanged. A received sequence is newer when the unsigned 16-bit distance `(received - stored) mod 65536` is in the range 1 through 32767. An equal sequence, and a distance of 32768 through 65535, is not newer and MUST be ignored. This keeps a withdrawal and a following advertisement ordered when propagation reorders them.

The entry carries the track hashes, the subscribe parameters, and the namespace and track-name octets. The octets let the origin relay construct the {{MOQT}} subscribe toward the publisher. Other relays can forward the entry without interpreting the name. A receiver MUST recompute the hashes from the name octets and MUST treat a mismatch as a malformed message.

Policy MAY filter subscribe advertisements the way it filters announces. An origin relay that never receives a subscribe does not forward objects for it. That is how a deployment keeps a publisher inside a region or a service class.

On receipt, the origin relay compares the subscribe with the announce information base. Tuple hashes are compared in order. A shorter namespace matches when each of its tuples equals the corresponding tuple of the longer name. An exact track match uses the full-name hash. A match causes the origin relay to subscribe toward the publisher, if it has not already, and to build a subscriber node set toward the source node of the subscribe.

A withdrawal removes the entry and updates the forwarding information base. The source node sends the withdrawal when its local subscribers for that track are gone.

## Forwarding Information Base

The forwarding information base is local. It is not encoded as an information-base message.

For each remote Node ID the node keeps the peering session that path selection chose. For each object flow the node keeps the mapping from an ingress subscriber-node-set identifier to the egress session and the egress identifier. A local subscriber is represented by a zero session identifier and a zero set identifier, which means the object is delivered to the {{MOQT}} stack on this node.

The table is updated when a node advertisement changes the best session, when a subscribe is added or removed, and when a subscriber node set arrives. An object stream that is already open keeps its previous egress until that stream ends. A new stream, and every datagram, uses the session currently in the table.

## Subscriber Node Set

The subscriber node set is the data-plane description of who needs a flow. It lists subscriber-relay Node IDs. It does not list the hops between them. Each hop looks those Node IDs up in the node information base and chooses the next data session.

The sender allocates a 32-bit identifier for the set on the session that will carry the objects. The identifier starts at 1 and increases. It MAY skip values. It wraps to 1 after 4294967294. Zero is reserved and means "no set". The same identifier is updated in place when subscribers are added or removed, so object streams that already cite the identifier stay valid.

The set is advertised on the control stream of the data session, or of the combined session, that will receive the objects. It is not propagated as an information base. When the receiving node is itself listed, it delivers matching objects to local subscribers, using the full-name hash carried on the object header. For every other Node ID in the set, it builds an egress set toward the chosen next hop and advertises that egress set on that next session.

A withdrawal retires one identifier on that session. Ending the session retires every identifier learned on it.

Objects MAY arrive before the set advertisement that names their identifier. The receiver SHOULD hold those objects until the advertisement arrives, and MUST discard them if the session ends or the identifier is withdrawn first.

# Names and Hashes {#names}

Namespace tuples and track names are opaque octet strings, in the same order {{MOQT}} uses. Relays hash them so that forwarding state and object headers stay fixed size.

The hash function is CityHash64 {{CITYHASH}} over the octet string. An empty string hashes as CityHash64 of zero octets.

The namespace hash is CityHash64 of the concatenation of the tuple octets, with no separator between tuples. The name hash is CityHash64 of the track-name octets. The full-name hash combines those two values, starting from zero:

~~~
hash_combine(seed, value):
    seed = seed XOR (value + 0x9e3779b9 + (seed << 6) + (value >> 2))
    all arithmetic is modulo 2^64

full_name_hash = 0
hash_combine(full_name_hash, namespace_hash)
hash_combine(full_name_hash, name_hash)
~~~
{: title="Full-name hash" }

Prefix matching uses the CityHash64 of each tuple, compared in order. A namespace A is a prefix of namespace B when A has no more tuples than B and each tuple hash of A equals the tuple hash of B at the same index.

# Connection Establishment

## Transport

The connection uses {{QUIC}} with the TLS handshake specified by {{QUIC-TLS}}. Implementations MUST NOT negotiate a TLS version older than TLS 1.3 {{TLS}}. The ALPN token MUST be `moq-peering`.

Either node MAY open the connection. The node that opens it is the initiator and sends CONNECT. The node that accepts it sends CONNECT_RESPONSE.

## Authentication {#authentication}

Authentication and authorization are part of session setup and finish before information bases are exchanged. Every session uses mutual TLS. A deployment MAY also use a token for authentication and authorization. The token is OPTIONAL. When the acceptor's policy does not require one, the mutual TLS identity is sufficient to authorize the session.

* Each node presents a certificate in the TLS handshake and MUST authenticate the peer.
* The initiator MUST NOT send CONNECT until the handshake has completed and the peer certificate has been accepted.
* The acceptor MUST NOT send peering messages, and MUST NOT accept CONNECT, until it has authenticated the initiator.
* A failed mutual TLS authentication closes the QUIC connection. No information-base state is created.
* When a token is used, the initiator places it in CONNECT. The acceptor checks it before accepting the session. The token MAY identify the peer and MAY authorize the Node ID and the requested session mode.
* A missing token that the policy requires, a token that fails authentication, or a token that does not authorize the session is rejected with response code Not Authorized. The acceptor then closes the connection. No information-base state is created.

Certificate material is configuration. Peering messages do not carry certificates or private keys, and implementations MUST NOT embed that material in source. Before use, the certificate MUST satisfy all of the following:

* The current time is within the certificate validity period.
* The signature uses SHA-256 or a stronger hash. MD5 and SHA-1 signatures MUST be rejected.
* An RSA key is at least 2048 bits. An elliptic-curve key uses P-256 or a stronger curve.
* The certificate chains to a trust anchor configured for this peering domain, or matches a peer credential that was configured explicitly.

A self-signed certificate is suitable only where every peer is configured to trust that exact certificate, such as a laboratory or a closed relay domain. It is not a substitute for a trust anchor on an open network.

Mutual TLS establishes the peer identity. CONNECT carries the Node ID, the requested session mode, and the OPTIONAL token. The acceptor binds the Node ID to the mutual TLS identity and, when a token is present, to that token. A Node ID that the policy does not allow for that identity is rejected with response code Not Authorized. A requested mode that the policy does not allow is rejected with response code Peering Mode Not Allowed. The token is an opaque octet string. Its format and the authority that issues it are deployment policy. Implementations MUST NOT embed tokens in source.

Deployments SHOULD use the key-exchange groups provided by their QUIC stack for TLS 1.3, including a hybrid post-quantum group when the stack and the peer both support one. Signature algorithms and certificate keys remain the ones listed above.

## Handshake Messages

After the QUIC handshake, the initiator opens the control stream and sends CONNECT. The message contains the session mode, the initiator's own node information with an empty path, and the OPTIONAL authentication and authorization token. The acceptor evaluates the mutual TLS identity and that token, then responds with CONNECT_RESPONSE. On success the response contains the acceptor's own node information, again with an empty path. On failure the response contains only the response code, and the acceptor closes the connection.

A control session or a mode Both session then synchronizes state. Each side sends the node, announce, and subscribe entries it is willing to advertise to that peer. The two directions are independent and MAY occur in either order. A data session does not send that synchronization. It sends subscriber node sets later, as object flows are created.

~~~
Initiator                         Acceptor
   |                                 |
   |-------- QUIC + mutual TLS ----->|
   |                                 |
   |-------- CONNECT --------------->|  OPTIONAL token
   |<------- CONNECT_RESPONSE -------|
   |                                 |
   |==== information bases =========>|   (Control or Both only)
   |<=== information bases ==========|
~~~
{: artwork-align="center" artwork-name="Session setup" }

# Path Selection

For each Node ID, the node compares the candidates advertised by its sessions. The first of these tests that differs chooses the candidate:

1. Lower selection cost. The cost is the sum of metrics. When the next-hop session is configured with a metric greater than the local node metric, the difference is added.
2. Fewer path items.
3. Lower sum of smoothed round-trip times.

When all three are equal, the node keeps the candidate it already selected. A repeated advertisement does not move existing object streams.

Changing a session metric recomputes the affected paths and re-advertises the local node, and the other nodes known on that session, with the new cost.

The inputs available to selection grow over time. Load, geographic policy, and reachability probes can refine the metric that a node advertises. This document fixes the comparison order so those refinements have a stable effect: they change the metric or the measured delay, and every node applies the same three tests.

# Data Forwarding

Objects move from the origin relay to each subscriber relay. Intermediate Via nodes do not parse {{MOQT}} object payloads. They read the peering header, look up the subscriber node set, and write the same payload bytes on the next sessions. The origin and subscriber relays are the points that convert between {{MOQT}} and this encapsulation.

The origin relay builds one subscriber node set per egress data session. The set contains the subscriber relays whose best path uses that session. The origin then sends the objects on that session with the set identifier in the peering header.

A Via or Edge that receives the set splits it. Node IDs that share the same next hop are placed in one egress set. The egress set is advertised on that next session with a new session-local identifier, and the node records the mapping from the ingress identifier to that egress identifier. If the node's own Node ID is in the set, the full-name hash in the object header selects the local {{MOQT}} subscribers. The peering header is removed before those bytes are handed to {{MOQT}}.

~~~
Publisher
   |  MOQT objects
   v
Origin Edge
   |  SNS 1 = { s-relay A, s-relay B }
   v
Via
   |  SNS 7 = { s-relay A }          SNS 8 = { s-relay B }
   +----------------+----------------+
   v                                 v
s-relay A                          s-relay B
   |  MOQT objects                    |  MOQT objects
   v                                  v
Subscribers                        Subscribers
~~~
{: artwork-align="center" artwork-name="Subscriber node sets along one flow" }

## Pipeline Forwarding {#pipeline-forwarding}

Datagram objects are forwarded as whole datagrams. A datagram that does not fit the next hop is dropped. This protocol does not fragment datagrams. Publishers that need to cross a smaller maximum transmission unit send objects on streams, or send datagrams that fit the smallest hop.

A stream is pipelined. The first bytes of a new unidirectional stream carry a peering header. Every following byte on that stream is payload and is written through without a further peering header. A relay does not reassemble the {{MOQT}} object before forwarding. Reassembly is the subscriber's job, and the job of a relay that has chosen to cache. A caching relay acts as a {{MOQT}} subscriber and publisher on that track.

A new {{MOQT}} group or subgroup arrives as a new QUIC stream. The relay mirrors that transition: the new stream gets a new peering header, and the previous stream ends. One active peering stream represents the current stream for that flow on a session.

The time-to-live in a new-stream header applies to the objects on that stream. The timer for an object starts when the object is received. The priority in that header is the priority of the egress QUIC stream and the priority offered to local {{MOQT}} subscribers.

## Opening a Flow

When the origin relay has both a publisher and at least one matching subscribe, it:

1. Groups the subscriber relays by the data session path selection chose.
2. Allocates a subscriber node set identifier on each of those sessions and advertises the set.
3. Sends object bytes with that identifier in the header.

A later subscribe that uses an existing session is added to the existing set, under the same identifier. A subscribe that is the last one on a session withdraws the identifier.

# Message Encoding

Octets are sent in network byte order. Unless a field states otherwise, multi-byte integers are unsigned and big-endian. A binary64 value is the IEEE 754 encoding of that floating-point number, also big-endian.

Diagrams name a field and the size in octets. `varint` is the variable-length integer defined in this section. A field in brackets is present only when the condition in the text is met. A repeated field continues until the enclosing message length is exhausted, unless a count is given.

## Variable-Length Integers {#varint}

Contact lengths use a variable-length integer of one to nine octets. The shortest encoding MUST be used. Let `bit_width(v)` be zero when `v` is zero, and otherwise one plus the index of the highest set bit.

* If `v` is zero, the length `L` is 1. Otherwise `L` is the minimum of 9 and `floor((bit_width(v) + 6) / 7)`.
* When `L` is 9, the encoding is the octet `0xFF` followed by `v` as eight octets.
* When `L` is 1, the encoding is the single octet `v`. Values 0 through 127 use this form.
* Otherwise the encoding is `L` octets. Write `v` into the most significant `L` octets of a 64-bit big-endian integer, which is `v` shifted left by `(8 - L) * 8`. Then set the high `(L - 1)` bits of the first octet by OR with the low eight bits of `0xFF << (9 - L)`.

A decoder reads the run of leading one bits in the first octet. Eight leading ones mean a nine-octet encoding and a 64-bit value in the following eight octets. `N` leading ones for `N` from 0 through 7 mean a length of `N + 1`. The value is the low `(8 - L)` bits of the first octet followed by the remaining `L - 1` octets. An encoding that is not the shortest form, or that sets a bit the encoder leaves clear, MUST be rejected.

## Common Header

Every control message begins with this header. Object payloads do not.

~~~
Common Header {
  Protocol Version (1) = 1,
  Message Type (2),
  Message Length (4),
}
~~~
{: title="Common header" }

Protocol Version is 1. A receiver that does not support the version MUST close the connection.

Message Length is the number of octets after the header. It does not include the seven header octets. A receiver assembles a message by reading the header and then exactly Message Length octets. Control messages are concatenated on the bidirectional stream.

## Message Types {#message-types}

| Type | Name                   | Carried on                          |
|-----:|:-----------------------|:------------------------------------|
| 1    | CONNECT                | Control stream, first from initiator |
| 2    | CONNECT_RESPONSE       | Control stream, first from acceptor |
| 3    | DATA_OBJECT            | Reserved. Not sent as a control message. |
| 4    | NODE_INFO_ADV          | Control or Both session             |
| 5    | NODE_INFO_WD           | Control or Both session             |
| 6    | SUBSCRIBE_INFO_ADV     | Control or Both session             |
| 7    | SUBSCRIBE_INFO_WD      | Control or Both session             |
| 8    | ANNOUNCE_INFO_ADV      | Control or Both session             |
| 9    | ANNOUNCE_INFO_WD       | Control or Both session             |
| 10   | SUBSCRIBE_NODE_SET_ADV | Data session, or Both session       |
| 11   | SUBSCRIBE_NODE_SET_WD  | Data session, or Both session       |
{: title="Control message types" }

An unknown type is a connection error.

## Node Information {#node-info}

Node information is embedded in CONNECT and CONNECT_RESPONSE and is the body of the node advertisement and withdrawal messages. The path occupies whatever remains of the enclosing length. The number of path items is that remainder divided by 24. A remainder that is not a multiple of 24 is a malformed message.

~~~
Node Info {
  Node ID (8),
  Node Type (1),
  Contact Length (varint),
  Contact (..),
  Longitude (8),
  Latitude (8),
  Metric (8),
  Path Item (..) ...,
}

Path Item {
  Node ID (8),
  SRTT Microseconds (8),
  Metric (8),
}
~~~
{: title="Node information" }

Node Type is a value from {{node-types}}. Contact Length is a {{varint}} count of the following octets.

## CONNECT

CONNECT is the first message on the control stream. Any other first message is a connection error.

~~~
CONNECT Message {
  Common Header (type = 1),
  Peer Mode (1),
  Token Present (1),
  [Token Length (varint),
   Token (..)],
  Node Info (..),
}
~~~
{: title="CONNECT" }

Peer Mode is a value from the session mode table. Token Present is 1 when a token follows and 0 when mutual TLS alone is used. Any other value is a malformed message. Token Length is a {{varint}} count of the following token octets. The token is opaque. Node Info describes the initiator and has an empty path. The token fields come before Node Info so the node path can still occupy the remainder of the message.

## CONNECT_RESPONSE

CONNECT_RESPONSE is the first message the acceptor sends. Creating a unidirectional stream before it arrives is a connection error.

~~~
CONNECT_RESPONSE Message {
  Common Header (type = 2),
  Response Code (2),
  [Node Info (..)],
}
~~~
{: title="CONNECT_RESPONSE" }

Node Info is present only when Response Code is 0. It describes the acceptor and has an empty path.

| Code | Name                     | Meaning                                      |
|-----:|:-------------------------|:---------------------------------------------|
| 0    | No Error                 | The session is accepted.                     |
| 1    | Connect Error            | The connect request cannot be completed.     |
| 2    | Not Authorized           | The authenticated identity is not allowed.   |
| 3    | Peering Mode Not Allowed | The requested session mode is not allowed.   |
{: title="Response codes" }

## Node Advertisement and Withdrawal

~~~
NODE_INFO_ADV Message {
  Common Header (type = 4),
  Node Info (..),
}

NODE_INFO_WD Message {
  Common Header (type = 5),
  Node Info (..),
}
~~~
{: title="Node information messages" }

The withdrawal carries the same structure so the receiver can drop the matching candidate, including an inferior path, rather than every candidate for that Node ID. The path in a withdrawal is the path of the candidate being removed.

## Subscribe Information

~~~
SUBSCRIBE_INFO_ADV Message {
  Common Header (type = 6),
  Sequence (2),
  Source Node ID (8),
  Namespace Hash (8),
  Name Hash (8),
  Full Name Hash (8),
  Priority (1),
  Delivery Timeout (8),
  Expires (8),
  Forward (8),
  New Group Present (1),
  [New Group Request ID (8)],
  Track Name (..),
}

SUBSCRIBE_INFO_WD Message {
  Common Header (type = 7),
  Sequence (2),
  Source Node ID (8),
  Namespace Hash (8),
  Name Hash (8),
  Full Name Hash (8),
  Priority (1),
  Delivery Timeout (8),
  Expires (8),
  Forward (8),
  New Group Present (1),
  [New Group Request ID (8)],
  Track Name (..),
}
~~~
{: title="Subscribe information messages" }

Sequence is the source node's counter for this subscribe. Source Node ID is the subscriber relay. The three hashes are defined in {{names}}. Priority is the subscriber's priority. Delivery Timeout and Expires are milliseconds. Zero means the parameter is unset. Forward is zero to pause forwarding and non-zero to forward. New Group Present is 1 when New Group Request ID follows and 0 when it does not. Any other value is a malformed message.

~~~
Track Name {
  Tuple Count (1),
  Tuple Length (2),
  Tuple Octets (..),
  ...
  Name Length (2),
  Name Octets (..),
}
~~~
{: title="Track name" }

Tuple Count is the number of namespace tuples. Each tuple is a 16-bit length and that many octets. Name Length is a 16-bit length. Zero means the name is empty. Tuple Count and the lengths MUST fit in the message. A count or length that runs past Message Length is a malformed message.

## Announce Information

~~~
ANNOUNCE_INFO_ADV Message {
  Common Header (type = 8),
  Source Node ID (8),
  Full Name Hash (8),
  Track Name (..),
  Flags (1),
}

ANNOUNCE_INFO_WD Message {
  Common Header (type = 9),
  Source Node ID (8),
  Full Name Hash (8),
  Track Name (..),
  Flags (1),
}
~~~
{: title="Announce information messages" }

Source Node ID is the origin relay. Bit 0 of Flags is 0 for a single track and 1 for a namespace announcement. A namespace announcement has an empty track name. All other flag bits MUST be sent as zero and MUST be ignored on receipt.

## Subscriber Node Set

~~~
SUBSCRIBE_NODE_SET_ADV Message {
  Common Header (type = 10),
  SNS ID (4),
  Priority (1),
  Node Count (2),
  Node ID (8) ...,
}

SUBSCRIBE_NODE_SET_WD Message {
  Common Header (type = 11),
  SNS ID (4),
}
~~~
{: title="Subscriber node set messages" }

SNS ID is the session-local identifier. Priority is the priority to apply to the flow. Node Count is the number of following Node IDs. The list is a set: order is not significant, and a sender MUST NOT repeat a Node ID. The receiver looks up each Node ID in the node information base. Node IDs that are not known are kept with the set until a later node advertisement makes a next hop available, or until the set is withdrawn.

## Data Headers

Object bytes are carried in QUIC DATAGRAM frames and on unidirectional streams. They are not carried on the bidirectional control stream.

A datagram and the first bytes of a new stream start with a data header. Header Length counts every octet of the header, including itself. The payload starts at that offset. Header Length MUST NOT exceed 255, and for the types defined here it is 14 for a datagram and 19 for a new stream.

~~~
Data Header {
  Header Length (1),
  Data Type (1),
  ... type-specific fields ...,
}
~~~
{: title="Data header" }

| Type | Name             | Header length | Use |
|-----:|:-----------------|--------------:|:----|
| 0    | DATAGRAM         | 14            | One datagram object. |
| 1    | EXISTING_STREAM  | 0             | Not encoded. Bytes after a new-stream header have no peering header. |
| 2    | NEW_STREAM       | 19            | First bytes of a unidirectional stream. |
{: title="Data types" }

### Datagram

~~~
DATAGRAM {
  Header Length (1) = 14,
  Data Type (1) = 0,
  SNS ID (4),
  Full Name Hash (8),
  Payload (..),
}
~~~
{: title="Datagram object" }

The payload is the remainder of the QUIC datagram. SNS ID selects the subscriber node set on this session. Full Name Hash selects local subscribers when this node is in the set.

### New Stream

A unidirectional stream MUST begin with NEW_STREAM. A stream that does not is reset. The header is not repeated. Every octet after the header, on that stream, is payload.

~~~
NEW_STREAM {
  Header Length (1) = 19,
  Data Type (1) = 2,
  SNS ID (4),
  Full Name Hash (8),
  Priority (1),
  TTL Milliseconds (4),
  Payload (..),
}
~~~
{: title="New stream header" }

Priority is the QUIC priority of the egress streams created from this stream. TTL Milliseconds is the object lifetime described in {{pipeline-forwarding}}.

### Existing Stream Bytes

After NEW_STREAM, further payload on the same QUIC stream is sent with no peering header. The SNS ID, full-name hash, priority, and time-to-live stay those of the NEW_STREAM header that opened the stream. An implementation classifies those bytes as existing-stream data locally. It does not put Data Type 1 on the wire.

# Error Handling

Transport failures and protocol violations close the QUIC connection or reset the offending stream, using an application error code.

| Code | Name                    | Where | Meaning |
|-----:|:------------------------|:------|:--------|
| 1    | CLOSE                   | Connection | The endpoint is closing the session. |
| 2    | REDIRECT                | Connection | The peer SHOULD move to another relay. |
| 8    | NOT_AUTHORIZED          | Connection | Authentication or policy refused the peer. |
| 32   | CONNECT_MISSING         | Connection | The first control message was not CONNECT. |
| 33   | CONNECT_RESP_MISSING    | Connection | A unidirectional stream was opened before CONNECT_RESPONSE. |
| 34   | INVALID_CTRL_MSG_TYPE   | Connection | The message type is unknown. |
| 35   | INVALID_ENCODING        | Connection or stream | A length, version, or field is malformed. |
| 36   | INVALID_START_OF_STREAM | Stream | A new stream did not start with NEW_STREAM. |
| 128  | SWITCH_NEW_STREAM       | Stream | The acceptor reset the previous control stream. |
{: title="QUIC application error codes" }

A CONNECT_RESPONSE with a non-zero response code refuses the session. The acceptor closes the connection after sending it. Response code 2 corresponds to a peer that completed mutual TLS and then failed token authentication, token authorization, or the Node ID policy. A TLS failure does not produce CONNECT_RESPONSE, because CONNECT is not sent when the handshake fails.

# Operational Considerations

## Redirecting Clients

Source routing by subscriber node set works best when subscribers to the same track share Edge nodes. A load balancer that spreads those subscribers across many Edges enlarges the set. An Edge that sees the same subscribe on a nearby Edge MAY redirect the {{MOQT}} client with GOAWAY and a new connection URL, when capacity allows. The information bases provide the subscribe and node data for that decision.

## Subscribe Churn

A subscriber that leaves and rejoins quickly would otherwise withdraw and re-advertise a subscribe across the control plane. A subscriber relay SHOULD delay a withdrawal for a short local interval. If the client subscribes to the same track again before the interval ends, the relay cancels the withdrawal. The delay is a local timer. It is not negotiated and MUST be bounded so a departed subscriber does not keep receiving objects for long. Five seconds is a reasonable default.

# Security Considerations

Mutual TLS, as specified in {{authentication}}, authenticates every peering session. An OPTIONAL token in CONNECT provides additional authentication and authorization. A node that skips verification of the peer certificate accepts a session from any endpoint that completes the handshake and can then inject node, announce, and subscribe state. Implementations MUST authenticate the peer before CONNECT. A token is a credential. Implementations MUST NOT log it, and they MUST treat a missing or rejected token as Not Authorized when local policy requires one.

The certificate checks in {{authentication}} exclude expired credentials, weak public keys, and MD5 or SHA-1 signatures. Trust anchors and any explicitly trusted self-signed certificates are deployment configuration. A self-signed certificate used beyond a closed domain will not be accepted by a peer that requires a chain to a known anchor.

The authenticated identity is bound to the Node ID in CONNECT. Without that binding, a peer that holds a valid certificate could advertise a Node ID it does not own and attract object flows. Policy at the acceptor enforces the binding and returns Not Authorized when it fails.

Control peering distributes the names of tracks and the identities of the relays that publish or subscribe. Filtering announce and subscribe advertisements is the mechanism that keeps a track inside a region or a customer boundary. A missing filter is a data leak, because an origin relay that learns a subscribe will forward objects toward that subscriber relay.

Object payloads are opaque to intermediate relays and are protected by the QUIC session on each hop. This protocol does not add a second encryption layer. End-to-end confidentiality and integrity of {{MOQT}} objects are the responsibility of the application and of {{MOQT}}, not of the peering encapsulation. Each hop can read the payload bytes it forwards.

The subscriber node set tells a data peer which Edge nodes receive a flow. That is visible to every hop on the data path. Deployments that treat the set of receivers as sensitive keep data sessions inside the same trust domain that already carries the objects.

An implementation MUST bound the memory used for information bases, for subscriber node sets, and for objects that arrive before their set advertisement. An unbounded buffer is a denial-of-service vector.

# IANA Considerations

## ALPN Identification

IANA is requested to add the following entry to the "TLS Application-Layer Protocol Negotiation (ALPN) Protocol IDs" registry:

| Protocol | Identification Sequence | Reference |
|:---------|:------------------------|:----------|
| Media over QUIC Relay Peering | `moq-peering` | This document |
{: title="ALPN identification" }

## Peering Registries

IANA is requested to create a "MOQ Relay Peering" registry group containing the registries below. New registrations in each registry use the Specification Required policy {{RFC8126}}.

### Message Type Registry {#iana-message-types}

The registry covers the 16-bit message type in the common header. Values 0 and 12 through 65535 are unassigned. Values 1 through 11 are assigned by {{message-types}}.

### Session Modes

The registry covers the 8-bit peer mode in CONNECT. Values 0, 1, and 2 are assigned by the session mode table. Values 3 through 255 are unassigned.

### Node Type Registry {#iana-node-types}

The registry covers the 8-bit node type. Values 0, 1, and 2 are assigned by {{node-types}}. Values 3 through 255 are unassigned.

### Response Codes

The registry covers the 16-bit response code in CONNECT_RESPONSE. Values 0 through 3 are assigned by the response code table. Values 4 through 65535 are unassigned.

### QUIC Application Error Codes

The registry covers the application error codes used with this ALPN. The values in the error code table are assigned by this document. Unlisted values are unassigned.

--- back

# Acknowledgments

The peering design reflected here was developed alongside the moq-peering relay library.

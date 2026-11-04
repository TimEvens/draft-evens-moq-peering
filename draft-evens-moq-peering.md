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

contributor:
#- name: First Last
#  org:  Cisco
#  email:  email@cisco.com

normative:
  QUIC: RFC9000
  MOQT: I-D.ietf-moq-transport

informative:

--- abstract

This document defines the {{MOQT}} relay peering protocol (MOQRP) that relays use to
interconnect between each other. Relay interconnections enable
forwarding of published objects to one or  more subscribers that span
one or more relays. The protocol defines a highly scalable and efficient communication
between the relays to support low latency real-time publishers and subscribers over
a distributed relay network.

--- middle

# Introduction
{{MOQT}} defines client/server interactions and messaging, but only loosely defines relay
interactions. The relay hierarchy is also left undefined. The publish/subscribe model supports
hop-by-hop topologies, but it often relies on a loop free topology. Propagation
of announcements and subscribes and forming a loop free topology introduces race conditions
that cause suboptimal data forwarding paths. In some cases, this can result in an outage for
some subscribers.

{{MOQT}} focuses on client-to-edge relay communication and therefore does not provide enough
information needed for global forwarding decisions by relays.

Relays introduce propagation delays as traffic traverses a relay. Avoiding unnecessary relays
is desirable to achieve efficient and optimized paths between publisher and subscribers.

This document describes a protocol that is used to establish and maintain a data-plane
to deliver {{MOQT}} published objects to {{MOQT}} subscribers while supporting the diverse
enterprise, service provider, SaaS provider, CDN provider, ... use-cases.

## Flat Topology
A flat topology is where both publisher and all subscribers are connected to the same relay or when one relay
meshes with all subscriber relays.

~~~ aasvg
                   ┌──────────────┐
                   │   Publisher  │
                   └──────────────┘
                           │
                           │
                           ▼
                      ┌─────────┐
        ┌─────────────│  Relay  │──────────────┐
        │             └─────────┘              │
        │                  │                   │
        ▼                  ▼                   ▼
┌──────────────┐    ┌──────────────┐   ┌──────────────┐
│ Subscriber 1 │    │ Subscriber 2 │   │ Subscriber 3 │
└──────────────┘    └──────────────┘   └──────────────┘
~~~
{: artwork-align="center" artwork-name="Flat Relay Topology"}

The flat topology is not practical considering where subscribers are located and
the time it takes to redirect/GOAWAY subscribers to the origin publisher relay.

**It has the following limitations:**

* Does not support multi-publisher where each publisher is connected to a different
  relay
* Single relay is limited to its vertical scale, which will limit the number of subscribers
  and peering relay connections it can handle
* A publisher relay to all subscriber relays results in (n-1) scale challenges
* Data is duplicated over the same IP forwarding paths, which is inefficient for those paths

## Spanning-Tree Topology

An alternative approach to a flat topology is to use spanning-tree. This has the advantage of a
distributed model where relays build the forwarding plane based on received subscriber and/or
announcements. In this model, announcements are flooded to every relay. In a small and
strategically engineered peering configuration, the forwarding plane does work okay. Although,
in practice, forwarding plane will need to support multiple topologies to facilitate:

* **business polices**, for example some constrains to enforce a specific forwarding plane to stay within country
* **traffic steering** to work around network problem points, such as keeping traffic flows
  on-net via the same cloud provider to maintain SLA with low loss and latency. Another common
  traffic steering use-case is to traffic engineer client edge communication to use a specific upstream network
  provider (e.g. classic SD-WAN use-cases)
* **load balancing** to distribute the aggregated load caused by spanning-tree selection of converged relays.
  A single relay in the middle cannot be expected to handle everything, for example all traffic from India
  to the United States

~~~ aasvg
                      ┌────────────┐
                      │ Publisher  │
                      └────────────┘
                             │
                             ▼
                      ┌────────────┐
              ┌───────│Origin Relay│────────┐
              │       └────────────┘        │
              │                             │
┌─────────────┼───────────┐   ┌─────────────┼───────────┐
│             ▼           │   │             ▼           │
│        ┌────────┐       │   │        ┌────────┐       │
│        │Relay 1 │       │   │        │Relay 1 │       │
│        └──┬─┬───┘       │   │        └──┬─┬───┘       │
│      ┌────┘ └────┐      │   │      ┌────┘ └────┐      │
│      ▼           ▼      │   │      ▼           ▼      │
│ ┌─────────┐ ┌─────────┐ │   │ ┌─────────┐ ┌─────────┐ │
│ │ Relay 2 │ │ Relay 3 │ │   │ │ Relay 2 │ │ Relay 3 │ │
│ └─────────┘ └─────────┘ │   │ └─────────┘ └─────────┘ │
│      │           │      │   │      │           │      │
│      ▼           ▼      │   │      ▼           ▼      │
│ ┌───────┐     ┌───────┐ │   │ ┌───────┐     ┌───────┐ │
│ │ SUB-1 │     │ SUB-2 │ │   │ │ SUB-1 │     │ SUB-2 │ │
│ └───────┘     └───────┘ │   │ └───────┘     └───────┘ │
│                         │   │                         │
│ US-WEST (PDX)           │   │           US-EAST (IAD) │
└─────────────────────────┘   └─────────────────────────┘
~~~
{: artwork-align="center" artwork-name="Spanning-Tree Relay Topology"}

While spanning-tree is a simple topology it does suffer from the above challenges resulting in more complex
workarounds that involve multiple topologies that use a flooding based protocol.

## Vector Based Topology
A vector based topology is a topology that computes one or more local topologies based on its received information
from its peers. The computed topology is based on attribute selection, often in order of preference, to generate
a topology that will be used to forward traffic to subscribers. Each node in the network generates its own
representation of the topology. Loops are avoided in the computed topology by filter and exclusion of looped
information. Detection of looped information is a simple process of seeing self in the information advertised
and received.

~~~ aasvg
┌─────────────────────────┐   ┌─────────────────────────┐
│    Singapore (SIN)      │   │     ┌────────────┐      │
│                         │   │     │ Publisher  │      │
│                         │   │     └────────────┘      │
│                         │   │            │            │
│                         │   │            ▼            │
│       ┌────────┐        │   │     ┌────────────┐      │
│       │Via xyz │◀───────┼───┼─────│Origin Edge │      │
│       └────────┘        │   │     └────────────┘      │
│            │            │   │                         │
│            │            │   │ India (BLR)             │
└────────────┼────────────┘   └─────────────────────────┘
┌────────────┼────────────┐   ┌─────────────────────────┐
│            ▼            │   │                         │
│       ┌─────────┐       │   │                         │
│       │  Via 1  │       │   │                         │
│       └─────────┘       │   │                         │
│            │            │   │                         │
│      ┌─────┴─────┬──────┼───┼──────┬───────────┐      │
│      ▼           ▼      │   │      ▼           ▼      │
│ ┌─────────┐ ┌─────────┐ │   │ ┌─────────┐ ┌─────────┐ │
│ │ Edge x  │ │Edge n(y)│ │   │ │ Edge x  │ │Edge n(y)│ │
│ └─────────┘ └─────────┘ │   │ └─────────┘ └─────────┘ │
│      │           │      │   │      │           │      │
│      ▼           ▼      │   │      ▼           ▼      │
│ ┌───────┐     ┌───────┐ │   │ ┌───────┐     ┌───────┐ │
│ │ SUB-1 │     │ SUB-2 │ │   │ │ SUB-1 │     │ SUB-2 │ │
│ └───────┘     └───────┘ │   │ └───────┘     └───────┘ │
│                         │   │                         │
│ US-WEST (PDX)           │   │            US-EAST (IAD)│
└─────────────────────────┘   └─────────────────────────┘
~~~
{: artwork-align="center" artwork-name="Vector Topology"}

The above topology illustrates a topology that is specific to publisher and the set of subscribers.
The vector topology supports real-time adjustments to optimize Via relays. In the
above diagram, US-EAST edge relays are directly peering with Via 1.

A US-EAST Via relay was computed as not needed based on the selection algorithm. If scale in US-EAST
grows or something changes that effects the selection algorithm, a Via might be injected to optimize
forwarding to US-EAST from India. It's possible that the use of a Via relay to reach US-EAST might change to reach
US-EAST from India via Frankfurt.

~~~ aasvg
                ┌────────────────────┐
                │   ┌────────────┐   │
                │   │ Publisher  │   │
                │   └────────────┘   │
                │          │         │
                │          ▼         │
                │   ┌────────────┐   │
             ┌──┼───│Origin Edge │───┼───┐
             │  │   └────────────┘   │   │
             │  │   India (BLR)      │   │
             │  └────────────────────┘   │
┌────────────┼────────────┐ ┌────────────┼────────────┐
│            ▼            │ │            ▼            │
│       ┌────────┐        │ │       ┌────────┐        │
│       │Via xyz │        │ │       │Via fra │        │
│       └────────┘        │ │       └────────┘        │
│Singapore   │       (SIN)│ │ Frankfurt  │       (FRA)│
└────────────┼────────────┘ └────────────┼────────────┘
┌────────────┼────────────┐ ┌────────────┼────────────┐
│            ▼            │ │            ▼            │
│       ┌─────────┐       │ │       ┌─────────┐       │
│       │  Via 1  │       │ │       │  Via 2  │       │
│       └─────────┘       │ │       └─────────┘       │
│            │            │ │            │            │
│      ┌─────┴─────┐      │ │      ┌─────┴─────┐      │
│      ▼           ▼      │ │      ▼           ▼      │
│ ┌─────────┐ ┌─────────┐ │ │ ┌─────────┐ ┌─────────┐ │
│ │ Edge x  │ │Edge n(y)│ │ │ │ Edge x  │ │Edge n(y)│ │
│ └─────────┘ └─────────┘ │ │ └─────────┘ └─────────┘ │
│      │           │      │ │      │           │      │
│      ▼           ▼      │ │      ▼           ▼      │
│ ┌───────┐     ┌───────┐ │ │ ┌───────┐     ┌───────┐ │
│ │ SUB-1 │     │ SUB-2 │ │ │ │ SUB-1 │     │ SUB-2 │ │
│ └───────┘     └───────┘ │ │ └───────┘     └───────┘ │
│                         │ │                         │
│ US-WEST (PDX)           │ │            US-EAST (IAD)│
└─────────────────────────┘ └─────────────────────────┘
~~~
{: artwork-align="center" artwork-name="Vector Topology Updated"}

## Traffic Steering
The concept of traffic steering (aka hair-pinning) is the ability to inject relay/proxy points in the middle
between edge-to-edge data forwarding to direct traffic to take a specific relay path that in turn uses
a specific IP forwarding path. Traffic steering is needed by many use-cases, such as, but not limited to:

* **Business Policy** - Often communication between publisher and subscriber must stay within designated
  geographical region(s). This may also include different levels of service, such as gold, silver, bronze. In these
  cases, the selection of allowing communication from publisher to subscriber may be denied, but in other cases it
  would be allowed as long as it guarantees IP packets to be forwarded in a specific way that ensures policy
  compliance.

* **Preferred Network** - Software Defined Networking (SD-WAN) use-cases often steer traffic to use specific ingress and
  egress network points to provide the best network path based on several factors.  This often includes direct
  networking agreements with customers to other customers, vendors, or cloud providers.

* **Load Balancing Networks** - Customers often have unequal bandwidth and have a need to leverage all available paths,
  which are not just based on IP routing best-path selections.

* **Avoiding Problem Areas** - Often a Software as a Service (SaaS) provider receives customer complaints that traffic
  via a specific network provider has loss/latency issues. The customer in this case requests the SaaS provider to
  resolve the issue. The SaaS provider cannot do this easily at the network level and therefore relies on the
  service application to direct the customer around the problem points. This often results in significant redirection
  to other regions and in some cases still does not work because IP traffic is asymmetric and moving ingress to
  a different IP path does not always result in the egress being changed to avoid the problem point. An example is where
  a customer is having problems with a specific service provider and request the SaaS to completely avoid that service
  provider for both ingress and egress IP forwarding.

# Terminology

{::boilerplate bcp14-tagged}

Commonly used terms in this document are described below.

Client:
: The party initiating a Transport Session.

Node:
: General term for a relay

Origin Relay:
: A relay that is directly connected to the publisher.

Via Relay:
: A relay that is acting as a relay between other relays.

Control Relay:
: A relay that is acting as a control server only.

Edge Relay:
: An edge relay is a relay that has both subscriber client connections and peering.

Stub Relay:
: A stub relay is a relay that has connections and only makes outbound peering connections. It does not accept
inbound peering connections.

Publisher:
: A client that publishes objects to a track

Subscriber:
: A client that receives objects from a track

# Information Bases

Each node relay, except Stub Relay, maintains information base tables. These tables are used
to form the publisher to subscriber forwarding.

Each node in the relay network makes an independent decision on which relay will be used as a next-hop. It does not
establish a source forwarding path end-to-end, instead it selects only the next-hop relay. Each next-hop relay
will make a decision on the next-hop it will use.

Selection attributes are used to compute the next-hop relays.

## Node Information Base (NIB)

The node information base table conveys information about nodes.

The table is indexed by `NodeId` that is encoded as an unsigned 64bit number.

### NodeId
NodeId is a globally unique value that is configured by the end-user for each node.

The encoded format of the `NodeId` is an unsigned 64bit number. To facilitate textual
representation for easier assignment and reading. The `NodeId` can be represented
in one of the following textual formats:

| Format | Textual Value                         |
|:-------|:--------------------------------------|
 NidF1    | `<uint16>.<uint16>:<uint16>.<uint16>`
 NidF2    | `<uint16>.<uint16>:<uint32>`
 NidF3    | `<uint32>:<uint16>.<uint16>`
 NidF4    | `<uint32>:<uint32>`
{: title="Textual NodeId Formats" }

In the above formats that use dots, the dots are optional. If they are left off, it will be
treated as `uint32`.  If the dot is included, then the values between the colon are considered
unsigned 16bit values.

When converting the unsigned 64bit number to textual representation, the default
uses **NidF1**.

The implementation SHOULD provide a configuration option to change the default to the
preferred textual representation format.

### Node Structure

The node structure conveys relevant information needed by the selection algorithm.

Id:
: NodeId of the node as an unsigned 64bit number

Contact:
: String value that defines the contact information for this node. This **SHOULD** be the FQDN that resolves
A/AAAA/CNAME uniquely for the node. Peering will use this to establish
a connection to this node. This can be an IPv4 or IPv6 address.

Type:
: Node Type for the node.

BestViaRelays:
: An array of `NodeId`s of other nodes that are considered best to reach the node. This is based on the node itself
running reachability probing. The array has a fixed maximum number of via relays.

Longitude:
: Longitude of where the node is located, as a double/float value

Latitude:
: Latitude of where the node is located, as a double/float value

#### Node Types

Node type is encoded as an unsigned 8bit value.

| Value | Name | Description                                                                                                                                                                                                     |
|:------|:-----|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
 0     | Edge | Accepts inbound connections from clients and peers. Will establish outbound peering connections to other Nodes.
 1     | Via  | Accepts inbound connections from peers and will establish outbound connections to other peers. No client clients are allowed.
 2     | Stub | Accepts inbound connections from clients and will establish outbound connections to a preconfigured default set of nodes. This node does not receive in forwarding information bases. It does not compute next-hops.
{: title="Textual NodeId Formats" }

## Subscriber Information Base (SIB)
Nodes need to be aware of {{MOQT}} subscribes. In {{MOQT}} subscribes do not match a known publish track, so
the subscribe needs to be sent to the set of publishers that match the subscribe namespace tuple and name. The subscribe
is considered incomplete till it has been accepted by a publisher.

A subscribe is initially sent via a SIB advertisement via the control signaling peering session. Initially the
AcceptedBy `NodeId` is null. This results in nodes NOT storing this entry. Instead, the relays that receive this
will only send the SIB to peering sessions that are toward the matching publisher(s).

The origin publish implements the {{MOQT}} flow to subscribe to the publisher. If successful, the origin edge relay
sends an updated SIB with AcceptedBy set to itself.  In multiple publisher use-cases where the subscribe matches
many publishers, each of the origin edge relays do the same by sending an updated SIB with their nodeId as the
AcceptedBy NodeId. Each relay receives a copy of this and stores it in its SIB table.

In the case an additional publisher connects after another publisher has already been established, the additional
publisher origin relay should have state of the existing accepted SIB. It should then send an unsolicited SIB
with itself as AcceptedBy.

~~~
{
  full_hash (uint64),
  received_by_node_id (uint64),
  origin_node_id (uint64),
  accepted_by_node_id (uint64),
  namespace_tuple_hash (uint64[]),
  name_hash (uint64),
}
~~~
{: #sib-fields title="SIB Fields" }

* **full_hash** - hash of the namespace tuples and name
* **received_by_node_id** - node id of the node that the advertising node received the SIB from
* **origin_node_id** - node id of the originating node of the subscribe
* **accepted_by_node_id** - node id of the edge node that a publisher accepted the subscribe
* **namespace_tuple_hash** - Array of hashes for each namespace tuple
* **name_hash** - hash of the name only

Each node advertises {{sib-fields}} and based on `accepted_by_node_id` being greater than zero, it will store
the SIB into a table for state tracking and further lookups.

Each node maintains a SIB table that accepts multiples by AcceptedBy NodeIds. Relays can purge their state
when the accepted by nodeId no longer announces a track that matched, or upon unsubscribe.

Relays uses the SIB table to suppress duplicate subscribes based on full hash. As long as one subscribe matches, the relay will
not send a new SIB.

If a publisher joins after the client subscribe, the edge relay is aware of publish announces, so
it can store the SIB with a null AcceptedBy NodeId and when a new publish announce is received,
it can send the SIB. Storing the null AcceptedBy SIB has an expiry based on node specific settings.
Upon expiry, the null entry will be removed and a new SIB by the node with the subscriber is required
if the subscriber is still interested. Edge nodes should periodically send null AcceptedBy SIBs
if not accepted when subscribers are still waiting for a publisher.  The interval used to send periodic
SIBs in this case MUST be greater or equal to 30 seconds.

In multiple publisher use-cases, a publisher may start after SIBs have been sent.  To handle this case, the edge relay
that has a new publisher which matches a SIB, should then immediately send a SIB with AcceptedBy set.

## Publisher Information Base (PIB)

Nodes need to be aware of {{MOQT}} publish tracks. {{MOQT}} allows publishers to announce a partial
track name, for example a prefix. Publishers may not start publishing to a full track name until a subscribe
has been received by the publisher.  In this sense, the publisher may not know the full track name till
there is an interest request by a subscriber. The publisher may reject the subscribe, which would result
in no track being established towards a subscriber.

{{MOQT}} announce namespaces are therefore conveyed to all relays via publisher information base
information (PIB).  Polices are considered when sending and receiving PIB advertisements and therefore could be
filtered egress or ingress based on policy. Filtering PIBs allows nodes to compute a table that takes
into account various policies.

The PIB will be checked on every SIB advertisement. To enable fast lookups, each {{MOQT}} namespace tuple
is hashed using PIBHASH algorithm.

The PIB is a nested table that can be represented in a flat table as follows:

| Namespace Index           | Hash               | Parent Hash                | Origin NodeId | Namespace Tuple Value                   |
|:--------------------------|:-------------------|:---------------------------|:--------------|:----------------------------------------|
 Array index of this tuple | Hash of this tuple | Hash of the previous tuple | Origin NodeId | Opaque value of the tuple as byte array
{: title="PIB Table" }

In code the representation is likely to be implemented in a nested fashion to support the lookup order. The lookup
order on receiving a SIB involves iterating over each tuple in the SIB namespace to find a match on index and hash.

An example code implementation might look like the below.

~~~ c++
struct PibValue {
    uint64_t parent_hash;
    uint64_t origin_node_id;
    std::vector<uint8_t> value;
}

std::map<TupleIndex, std::map<PibHash, PibValue>> pib;
~~~

### PibHash Algorithm
TODO

## Advertisements

When a relay peers to another relay to exchange information bases, it is referred to as an information base peer (IBP).
IBP is used only for information base advertisements and exchanges. It does not forward data. Separate peering is used
for data forwarding. The IBP does not have to follow the data forwarding path and therefore can be more centralized
and focused on information base exchanges. IBP is required to maintain a connection to retain state of PIBs and SIBs
that have been advertised. Data peering does not require the connection to be maintained. Data peering can come and go
as needed. To minimize churn with flapping IBP, there is a negotiated grace period to allow the state
to linger before state is removed. If the IBP doesn't resume after the negotiated time period, all PIBs and SIBs will
be purged.

~~~ aasvg
             .───────────────.
       ┌───▶(    IBP Relay    )◀───┐
       │     `───────────────'     │
       │                           │
       │  IBP                 IBP  │
       │                           │
       ▼                           ▼
┌─────────────┐             ┌─────────────┐
│             │  DP (Data)  │             │
│   Edge R1   │◀───────────▶│   Edge R2   │
│             │             │             │
└─────────────┘             └─────────────┘
~~~
{: artwork-align="center" artwork-name="Information Base and Data Peering"}


## Selection Algorithm

# Data Forwarding
Edge relays with direct publishers maintain a subscribe table based on the SIB and NIB tables. They form a local
forwarding table based on the two, that takes into account policies and other constraints.

# Security Considerations {#security}
TODO: Expand this section

# IANA Considerations
TODO: Expand this section

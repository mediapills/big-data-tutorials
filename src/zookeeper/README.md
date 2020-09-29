#How it works

You may describe ZooKeeper as a replicated synchronization service with eventual consistency. It is robust, since the
persisted data is distributed between multiple nodes (this set of nodes is called an "ensemble") and one client
connects to any of them (i.e., a specific "server"), migrating if one node fails; as long as a strict majority of nodes
are working, the ensemble of ZooKeeper nodes is alive. In particular, a master node is dynamically chosen by consensus
within the ensemble; if the master node fails, the role of master migrates to another node.

#How writes are handled

The master is the authority for writes: in this way writes can be guaranteed to be persisted in-order, i.e., writes are
linear. Each time a client writes to the ensemble, a majority of nodes persist the information: these nodes include the
server for the client, and obviously the master. This means that each write makes the server up-to-date with the
master. It also means, however, that you cannot have concurrent writes.

The guarantee of linear writes is the reason for the fact that ZooKeeper does not perform well for write-dominant
workloads. In particular, it should not be used for interchange of large data, such as media. As long as your
communication involves shared data, ZooKeeper helps you. When data could be written concurrently, ZooKeeper actually
gets in the way, because it imposes a strict ordering of operations even if not strictly necessary from the perspective
of the writers. Its ideal use is for coordination, where messages are exchanged between the clients.

#How reads are handled

This is where ZooKeeper excels: reads are concurrent since they are served by the specific server that the client 
connects to. However, this is also the reason for the eventual consistency: the "view" of a client may be outdated,
since the master updates the corresponding server with a bounded but undefined delay.

#In detail

The replicated database of ZooKeeper comprises a tree of znodes, which are entities roughly representing file system
nodes (think of them as directories). Each znode may be enriched by a byte array, which stores data. Also, each znode
may have other znodes under it, practically forming an internal directory system.

#Sequential znodes

Interestingly, the name of a znode can be sequential, meaning that the name the client provides when creating the znode
is only a prefix: the full name is also given by a sequential number chosen by the ensemble. This is useful, for
example, for synchronization purposes: if multiple clients want to get a lock on a resource, they can each concurrently
create a sequential znode on a location: whoever gets the lowest number is entitled to the lock.

#Ephemeral znodes

Also, a znode may be ephemeral: this means that it is destroyed as soon as the client that created it disconnects. This
is mainly useful in order to know when a client fails, which may be relevant when the client itself has
responsibilities that should be taken by a new client. Taking the example of the lock, as soon as the client having the
lock disconnects, the other clients can check whether they are entitled to the lock.

#Watches

The example related to client disconnection may be problematic if we needed to periodically poll the state of znodes.
Fortunately, ZooKeeper offers an event system where a watch can be set on a znode. These watches may be set to trigger
an event if the znode is specifically changed or removed or new children are created under it. This is clearly useful
in combination with the sequential and ephemeral options for znodes.

#Where and how to use it

A canonical example of Zookeeper usage is distributed-memory computation, where some data is shared between client
nodes and must be accessed/updated in a very careful way to account for synchronization.

ZooKeeper offers the library to construct your synchronization primitives, while the ability to run a distributed
server avoids the single-point-of-failure issue you have when using a centralized (broker-like) message repository.

ZooKeeper is feature-light, meaning that mechanisms such as leader election, locks, barriers, etc. are not already
present, but can be written above the ZooKeeper primitives. If the C/Java API is too unwieldy for your purposes, you
should rely on libraries built on ZooKeeper such as cages and especially curator.

> \- [Luca Geretti](https://stackoverflow.com/users/859596/luca-geretti),
> ["Explaining Apache ZooKeeper"](https://stackoverflow.com/questions/3662995/explaining-apache-zookeeper)
> [[Stack Overflow](https://stackoverflow.com)]
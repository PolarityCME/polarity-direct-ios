# MVP-Primitive-2 (Samsung Server and iPhone client)

Listens on TCP :5555 and speaks CME1 line-delimited frames.

Handshake:
- Server sends: CME1|WELCOME <session>
- Client sends: CME1|HELLO|iPhone|P2
- Server replies: CME1|HELLO_ACK <session>

Messages:
- Client sends: CME1|TEXT|<message>
- Server echoes: CME1|ECHO <raw>

Run:
python3 server_p2.py

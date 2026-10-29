"""Keyless LAN UDP v2 messages; session tickets still bound input lifetime."""
import json

MAX_PACKET = 1400


def encode(payload):
    wire = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
    if len(wire) > MAX_PACKET:
        raise ValueError('Datagram too large')
    return wire


def decode(wire):
    if len(wire) > MAX_PACKET:
        raise ValueError('Datagram too large')
    def invalid(value):
        raise ValueError('Nonfinite JSON value')
    result = json.loads(wire, parse_constant=invalid)
    if not isinstance(result, dict) or type(result.get('v')) is not int or result['v'] != 2:
        raise ValueError('Unsupported protocol; use DuckPilot 0.4 or newer')
    return result


class Session:
    """One endpoint, monotonic sequence and short server-issued ticket lifetime."""
    def __init__(self, sid, address, now, ticket):
        self.sid, self.address = sid, address
        self.seq = -1
        self.seen = now
        self.ticket, self.ticket_at = ticket, now
        self.previous_ticket, self.previous_at = None, -1
        self.claimed = False
        self.input_at = None

    def rotate(self, ticket, now):
        self.previous_ticket, self.previous_at = self.ticket, self.ticket_at
        self.ticket, self.ticket_at = ticket, now

    def accept(self, message, address, now):
        sequence = message.get('seq')
        if (message.get('sid') != self.sid or address != self.address
                or type(sequence) is not int or not 0 <= sequence < 2**53
                or sequence <= self.seq):
            raise ValueError('Wrong session, endpoint or replayed sequence')
        valid = (message.get('ticket') == self.ticket and now-self.ticket_at <= .45)
        valid = valid or (self.previous_ticket is not None and message.get('ticket') == self.previous_ticket
                          and now-self.previous_at <= .45)
        if not valid:
            raise ValueError('Expired server ticket; reconnect or await heartbeat')
        self.seq, self.seen = sequence, now

"""Authenticated UDP messages. HMAC covers the exact UTF-8 payload bytes."""
import hashlib
import hmac
import json

MAX_PACKET = 1400


def encode(key, payload):
    body = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    signature = hmac.new(key, body.encode(), hashlib.sha256).hexdigest()
    wire = json.dumps({'p': body, 'h': signature}, ensure_ascii=False, separators=(',', ':')).encode()
    if len(wire) > MAX_PACKET:
        raise ValueError('Datagram too large')
    return wire


def decode(key, wire):
    if len(wire) > MAX_PACKET:
        raise ValueError('Datagram too large')
    envelope = json.loads(wire)
    if not isinstance(envelope, dict) or set(envelope) != {'p', 'h'}:
        raise ValueError('Invalid envelope')
    body, signature = envelope['p'], envelope['h']
    if not isinstance(body, str) or not isinstance(signature, str):
        raise ValueError('Invalid envelope values')
    expected = hmac.new(key, body.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        raise ValueError('Authentication failed')
    def invalid(value):
        raise ValueError('Nonfinite JSON value')
    result = json.loads(body, parse_constant=invalid)
    if not isinstance(result, dict) or result.get('v') != 1:
        raise ValueError('Unsupported protocol')
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

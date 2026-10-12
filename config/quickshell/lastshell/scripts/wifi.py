#!/usr/bin/env python3
"""
wifi.py - lastshell's iwd engine (the laptop's Wi-Fi picker). services/Wifi.qml
runs it only while the picker or the password dialog is open, or a connection
is still in flight, so between uses nothing of it is resident: no process, no
polling, no D-Bus match rules. iwd keeps scanning and roaming on its own.

It talks to iwd over D-Bus and doubles as iwd's passphrase agent. iwd routes an
agent request to the agent on the same connection as the Connect call, so the
passwords for the connects made here come back here.

    stdout  state {scanning, station, networks: [{name, type, signal, known, connected}]}
            result {name, ok, error}     a connect finished
            prompt {name} | null         iwd wants a passphrase we did not have
    stdin   scan
            connect {"name": ..., "passphrase": ...}   passphrase optional
            passphrase "<text>"          answers the open prompt
            cancel                       declines it

The picker asks for a new network's password up front and the agent hands it
over when iwd asks, so there is never a second prompt (the bug DankMaterialShell
fixed in PR #3743). A prompt only reaches the UI when iwd asks for something we
were not given.
"""

import json
import signal
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
import gi
from gi.repository import GLib

try:
    gi.require_version('GLibUnix', '2.0')
    from gi.repository import GLibUnix
    unix_signal_add = GLibUnix.signal_add
except (ValueError, ImportError):
    unix_signal_add = GLib.unix_signal_add

IWD = 'net.connman.iwd'
STATION = IWD + '.Station'
NETWORK = IWD + '.Network'
AGENT_PATH = '/us/lastra/lastshell/wifi_agent'


def emit(kind, value):
    print(kind, json.dumps(value), flush=True)


class Canceled(dbus.DBusException):
    _dbus_error_name = 'net.connman.iwd.Agent.Error.Canceled'


class Agent(dbus.service.Object):
    def __init__(self, bus, engine):
        super().__init__(bus, AGENT_PATH)
        self.engine = engine

    @dbus.service.method(IWD + '.Agent', in_signature='o', out_signature='s',
                         async_callbacks=('reply', 'error'))
    def RequestPassphrase(self, path, reply, error):
        self.engine.request_passphrase(str(path), reply, error)

    @dbus.service.method(IWD + '.Agent', in_signature='s', out_signature='')
    def Cancel(self, reason):
        self.engine.drop_prompt()

    @dbus.service.method(IWD + '.Agent', in_signature='', out_signature='')
    def Release(self):
        pass


class Engine:
    def __init__(self, loop):
        self.loop = loop
        self.bus = dbus.SystemBus()
        self.station = None          # object path of the wlan station
        self.pending = {}            # name -> passphrase entered before connecting
        self.prompt = None           # (name, reply, error) iwd is waiting on
        self.publish_id = 0
        self.agent = Agent(self.bus, self)
        self.manager = dbus.Interface(self.bus.get_object(IWD, '/net/connman/iwd'),
                                      IWD + '.AgentManager')
        self.manager.RegisterAgent(dbus.ObjectPath(AGENT_PATH))
        # all change notification is event-driven: one coalesced republish
        for name in ('InterfacesAdded', 'InterfacesRemoved'):
            self.bus.add_signal_receiver(self.changed, name,
                                         'org.freedesktop.DBus.ObjectManager', IWD)
        self.bus.add_signal_receiver(self.changed, 'PropertiesChanged',
                                     'org.freedesktop.DBus.Properties', IWD)
        self.publish()

    # --- iwd state ------------------------------------------------------
    def objects(self):
        om = dbus.Interface(self.bus.get_object(IWD, '/'), 'org.freedesktop.DBus.ObjectManager')
        return om.GetManagedObjects()

    def changed(self, *args):
        # iwd fires a burst of signals per scan or state change; publish once
        if not self.publish_id:
            self.publish_id = GLib.timeout_add(150, self.publish)

    def publish(self):
        self.publish_id = 0
        objs = self.objects()
        self.station = next((p for p, ifs in objs.items() if STATION in ifs), None)
        if not self.station:
            emit('state', {'scanning': False, 'station': 'off', 'networks': []})
            return False
        st = objs[self.station][STATION]
        ordered = dbus.Interface(self.bus.get_object(IWD, self.station), STATION).GetOrderedNetworks()
        nets = []
        for path, strength in ordered:
            n = objs.get(path, {}).get(NETWORK)
            if not n:
                continue
            nets.append({
                'name': str(n['Name']),
                'type': str(n['Type']),                 # open, psk, 8021x, wep
                'signal': int(strength) // 100,         # dBm
                'known': 'KnownNetwork' in n,
                'connected': bool(n.get('Connected', False)),
            })
        emit('state', {'scanning': bool(st.get('Scanning', False)),
                       'station': str(st.get('State', '')), 'networks': nets})
        return False

    def network_path(self, name):
        for path, ifs in self.objects().items():
            n = ifs.get(NETWORK)
            if n and str(n['Name']) == name and str(n.get('Device', '')) == self.station:
                return path
        return None

    # --- commands -------------------------------------------------------
    def scan(self):
        if self.station:
            dbus.Interface(self.bus.get_object(IWD, self.station), STATION).Scan(
                reply_handler=lambda: None, error_handler=lambda e: None)  # InProgress is fine

    def connect(self, name, passphrase=None):
        path = self.network_path(name)
        if not path:
            emit('result', {'name': name, 'ok': False, 'error': 'not in range'})
            return
        if passphrase:
            self.pending[name] = passphrase
        net = dbus.Interface(self.bus.get_object(IWD, path), NETWORK)

        def ok():
            self.pending.pop(name, None)
            emit('result', {'name': name, 'ok': True, 'error': ''})

        def fail(e):
            self.pending.pop(name, None)
            err = e.get_dbus_name() or ''
            msg = ('wrong password' if any(k in err for k in ('IncorrectPassphrase', 'InvalidKey', 'AuthenticationFailed'))
                   else 'wrong password?' if err.endswith('.Failed') and passphrase
                   else 'canceled' if err.endswith('Canceled') or err.endswith('Aborted')
                   else 'already connected' if err.endswith('AlreadyConnected')
                   else 'not in range' if err.endswith('NotFound')
                   else err.rsplit('.', 1)[-1] or 'failed')
            emit('result', {'name': name, 'ok': msg == 'already connected', 'error': msg})

        net.Connect(reply_handler=ok, error_handler=fail, timeout=120)

    # --- the agent ------------------------------------------------------
    def request_passphrase(self, path, reply, error):
        try:
            name = str(self.bus.get_object(IWD, path).Get(NETWORK, 'Name',
                                                          dbus_interface='org.freedesktop.DBus.Properties'))
        except dbus.DBusException:
            name = path
        if name in self.pending:
            reply(self.pending.pop(name))
            return
        self.drop_prompt()
        self.prompt = (name, reply, error)
        emit('prompt', {'name': name})

    def answer(self, passphrase):
        if self.prompt:
            _, reply, _ = self.prompt
            self.prompt = None
            reply(passphrase)
            emit('prompt', None)

    def drop_prompt(self):
        if self.prompt:
            _, _, error = self.prompt
            self.prompt = None
            error(Canceled())
            emit('prompt', None)

    def close(self):
        self.drop_prompt()
        try:
            self.manager.UnregisterAgent(dbus.ObjectPath(AGENT_PATH))
        except dbus.DBusException:
            pass
        self.loop.quit()

    def command(self, line):
        cmd, _, arg = line.strip().partition(' ')
        val = json.loads(arg) if arg else None
        if cmd == 'scan':
            self.scan()
        elif cmd == 'connect':
            self.connect(val['name'], val.get('passphrase'))
        elif cmd == 'passphrase':
            self.answer(val)
        elif cmd == 'cancel':
            self.drop_prompt()


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    try:
        engine = Engine(loop)
    except dbus.DBusException as e:
        emit('state', {'scanning': False, 'station': 'error: ' + (e.get_dbus_name() or str(e)), 'networks': []})
        return

    def on_stdin(fd, cond):
        line = sys.stdin.readline()
        if not line:              # the shell closed us
            engine.close()
            return False
        try:
            engine.command(line)
        except (ValueError, KeyError, TypeError, dbus.DBusException) as e:
            print(f'wifi.py: {line.strip().split(" ")[0]}: {e}', file=sys.stderr, flush=True)
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, on_stdin)
    unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: engine.close() or False)
    loop.run()


if __name__ == '__main__':
    main()

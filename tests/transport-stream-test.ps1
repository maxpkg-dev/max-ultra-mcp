# Verifies .NET stream assumptions on synthetic loopback sockets; does not load MAXScript or Max.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public static class MaxUltraStreamFixture {
    static void Check(bool condition, string message) {
        if (!condition) throw new Exception(message);
    }
    public static void Run() {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try {
            using (var sender = new TcpClient()) {
                sender.Connect(IPAddress.Loopback, ((IPEndPoint)listener.LocalEndpoint).Port);
                using (var receiver = listener.AcceptTcpClient()) {
                    var input = receiver.GetStream();
                    input.ReadTimeout = 500;
                    var output = sender.GetStream();
                    var buffer = new byte[8192];
                    var partial = Encoding.ASCII.GetBytes("REQUEST\tpartial");
                    output.Write(partial, 0, partial.Length);
                    int count = input.Read(buffer, 0, buffer.Length);
                    Check(count > 0 && count <= partial.Length, "Read must return available bytes without waiting for newline or full buffer");
                    string pending = Encoding.ASCII.GetString(buffer, 0, count);
                    var tail = Encoding.ASCII.GetBytes("\nCANCEL\tsecond\n");
                    output.Write(tail, 0, tail.Length);
                    while (!pending.EndsWith("second\n")) {
                        count = input.Read(buffer, 0, buffer.Length);
                        pending += Encoding.ASCII.GetString(buffer, 0, count);
                    }
                    Check(pending.Split('\n').Length == 3, "Both frames must be visible without a third write");
                    bool timedOut = false;
                    try { input.Read(buffer, 0, buffer.Length); } catch (IOException) { timedOut = true; }
                    Check(timedOut, "Idle synchronous read must honor ReadTimeout");

                    input.ReadTimeout = 10000;
                    using (var entered = new ManualResetEventSlim()) {
                        var blocked = Task.Run(() => {
                            entered.Set();
                            try { input.Read(buffer, 0, buffer.Length); } catch (IOException) { } catch (ObjectDisposedException) { }
                        });
                        entered.Wait();
                        receiver.Close();
                        Check(blocked.Wait(2000), "Closing shared client must release pending read");
                    }
                }
            }
            using (var writer = new TcpClient()) {
                writer.SendBufferSize = 1024;
                writer.Connect(IPAddress.Loopback, ((IPEndPoint)listener.LocalEndpoint).Port);
                using (var blockedPeer = listener.AcceptTcpClient()) {
                    blockedPeer.ReceiveBufferSize = 1024;
                    var stream = writer.GetStream();
                    stream.WriteTimeout = 500;
                    var bulk = new byte[4 * 1024 * 1024];
                    bool writeFailed = false;
                    try {
                        for (int index = 0; index < 256; index++) stream.Write(bulk, 0, bulk.Length);
                    } catch (IOException) { writeFailed = true; }
                    Check(writeFailed, "Non-reading peer must hit bounded write timeout");
                }
            }
        } finally { listener.Stop(); }
    }
}
'@
[MaxUltraStreamFixture]::Run()
Write-Output 'Transport stream fixtures passed: partial/coalesced frames, read deadline, close cancellation, and blocked writer (.NET Framework; no Max).'

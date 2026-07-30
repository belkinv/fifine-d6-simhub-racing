param(
    [Parameter(Mandatory = $true)]
    [string]$PropertyServerDll
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public sealed class GateStream : Stream
{
    private readonly TaskCompletionSource<bool> _entered =
        new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource<bool> _release =
        new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

    public Task Entered { get { return _entered.Task; } }
    public void Release() { _release.TrySetResult(true); }

    public override async Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        _entered.TrySetResult(true);
        await _release.Task.ConfigureAwait(false);
    }

    public override void Flush() { }
    public override Task FlushAsync(CancellationToken cancellationToken) { return Task.CompletedTask; }
    public override bool CanRead { get { return false; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return true; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position
    {
        get { throw new NotSupportedException(); }
        set { throw new NotSupportedException(); }
    }
    public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
    public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
}
'@

$dllPath = (Resolve-Path -LiteralPath $PropertyServerDll).Path
$assembly = [Reflection.Assembly]::LoadFrom($dllPath)
$clientType = $assembly.GetType('SimHub.Plugins.PropertyServer.Comm.Client', $true)
$ctor = $clientType.GetConstructors()[0]

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$tcpClient = [Net.Sockets.TcpClient]::new()
$connectTask = $tcpClient.ConnectAsync([Net.IPAddress]::Loopback, $port)
$peer = $listener.AcceptTcpClient()
$connectTask.GetAwaiter().GetResult()
$listener.Stop()

$client = $ctor.Invoke(@($null, $null, $tcpClient))
$gate = [GateStream]::new()
$writer = [IO.StreamWriter]::new($gate)
$writerField = $clientType.GetField('_writer', [Reflection.BindingFlags]'Instance,NonPublic')
$writerField.SetValue($client, $writer)
$send = $clientType.GetMethod('SendString', [Reflection.BindingFlags]'Instance,NonPublic')

$first = [Threading.Tasks.Task]$send.Invoke($client, @('first'))
if (-not $gate.Entered.Wait(2000)) {
    throw 'FAIL: the first write did not reach the controlled stream'
}

$second = [Threading.Tasks.Task]$send.Invoke($client, @('second'))
Start-Sleep -Milliseconds 200

if ($second.IsCompleted -or -not $tcpClient.Connected) {
    $gate.Release()
    try { $first.GetAwaiter().GetResult() } catch { }
    try { $second.GetAwaiter().GetResult() } catch { }
    throw 'FAIL: concurrent SendString was not serialized and disconnected the client'
}

$gate.Release()
[Threading.Tasks.Task]::WaitAll(@($first, $second), 5000) | Out-Null

if (-not $tcpClient.Connected) {
    throw 'FAIL: client disconnected after serialized writes'
}

$writer.Dispose()
$peer.Dispose()
$tcpClient.Dispose()
Write-Output 'PASS: concurrent SendString calls are serialized and the client remains connected'

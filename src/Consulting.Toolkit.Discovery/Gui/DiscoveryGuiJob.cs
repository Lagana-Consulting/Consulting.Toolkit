using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Security;
using System.Text;

namespace Consulting.Toolkit.Discovery {
    // The window owns its worker and descendants. Closing this job stops only
    // those processes, including any Windows PowerShell compatibility child.
    public sealed class DiscoveryProcessJob : IDisposable {
        private IntPtr handle;
        [StructLayout(LayoutKind.Sequential)] private struct BasicLimits {
            public long ProcessUserTime, JobUserTime;
            public uint Flags;
            public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] private struct IoCounters {
            public ulong ReadOperations, WriteOperations, OtherOperations;
            public ulong ReadBytes, WriteBytes, OtherBytes;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr security, string name);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr job, int type, ref ExtendedLimits info, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        public DiscoveryProcessJob() {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) {
                int error = Marshal.GetLastWin32Error(); Dispose(); throw new Win32Exception(error);
            }
        }
        public void Assign(Process process) {
            if (!AssignProcessToJobObject(handle, process.Handle)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public void Dispose() {
            if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
            GC.SuppressFinalize(this);
        }
        ~DiscoveryProcessJob() { Dispose(); }
    }

    // LOGON_NETCREDENTIALS_ONLY gives every network API in the worker the same
    // alternate credentials, including GroupPolicy APIs without -Credential.
    // Local identity and local filesystem permissions remain the caller's.
    public static class CredentialProcess {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] private struct StartupInfo {
            public int Size;
            public string Reserved, Desktop, Title;
            public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
            public ushort ShowWindow, ReservedSize;
            public IntPtr ReservedBytes, StandardInput, StandardOutput, StandardError;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ProcessInfo {
            public IntPtr Process, Thread;
            public uint ProcessId, ThreadId;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool CreateProcessWithLogonW(string user, string domain, IntPtr password,
            uint logonFlags, string application, StringBuilder command, uint creationFlags,
            IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

        public static Process Start(string identity, SecureString password, string executable,
            string arguments, string directory, DiscoveryProcessJob job) {
            if (String.IsNullOrWhiteSpace(identity) || password == null || password.Length == 0)
                throw new ArgumentException("Enter an account name and password.");
            string user = identity, domain = null;
            int separator = identity.IndexOf('\\');
            if (separator >= 0) {
                domain = identity.Substring(0, separator); user = identity.Substring(separator + 1);
                if (domain.Length == 0 || user.Length == 0 || user.IndexOf('\\') >= 0)
                    throw new ArgumentException("Use DOMAIN\\user or user@domain for the alternate account.");
            } else if (identity.IndexOf('@') <= 0 || identity.EndsWith("@", StringComparison.Ordinal)) {
                throw new ArgumentException("Use DOMAIN\\user or user@domain for the alternate account.");
            }
            var values = new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            foreach (System.Collections.DictionaryEntry item in Environment.GetEnvironmentVariables())
                values[(string)item.Key] = (string)item.Value;
            var block = new StringBuilder();
            foreach (var item in values) block.Append(item.Key).Append('=').Append(item.Value).Append('\0');
            block.Append('\0');
            IntPtr secret = IntPtr.Zero, environment = IntPtr.Zero;
            var info = new ProcessInfo();
            Process process = null;
            try {
                environment = Marshal.StringToHGlobalUni(block.ToString());
                // The only plaintext copy is this unmanaged buffer required by
                // Windows. Never create a managed password string or arguments.
                secret = Marshal.SecureStringToGlobalAllocUnicode(password);
                var startup = new StartupInfo();
                startup.Size = Marshal.SizeOf(typeof(StartupInfo));
                startup.Flags = 1; startup.ShowWindow = 0; // STARTF_USESHOWWINDOW, SW_HIDE
                var command = new StringBuilder("\"" + executable + "\" " + arguments);
                // Suspend until the process is assigned to our cancellation job.
                if (!CreateProcessWithLogonW(user, domain, secret, 2, executable, command,
                    0x08000404, environment, directory, ref startup, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                process = Process.GetProcessById((int)info.ProcessId);
                job.Assign(process);
                if (ResumeThread(info.Thread) == UInt32.MaxValue)
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return process;
            } catch {
                if (info.Process != IntPtr.Zero) TerminateProcess(info.Process, 1);
                if (process != null) process.Dispose();
                throw;
            } finally {
                if (secret != IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(secret);
                if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
                if (info.Thread != IntPtr.Zero) CloseHandle(info.Thread);
                if (info.Process != IntPtr.Zero) CloseHandle(info.Process);
            }
        }
    }
}

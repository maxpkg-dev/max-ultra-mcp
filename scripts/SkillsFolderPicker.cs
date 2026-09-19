// Native Explorer folder selection, invoked on the owning Max UI thread.
// Copyright (c) 2026 Lukianenko Vasyl
// Project website: https://3dground.net
// Developed by Lukianenko Vasyl
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MaxUltraMcp {
    public static class SkillsFolderPicker {
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        public static string Show(long ownerHandle) {
            IntPtr owner = new IntPtr(ownerHandle);
            uint ownerProcess;
            uint ownerThread = GetWindowThreadProcessId(owner, out ownerProcess);
            if (owner == IntPtr.Zero || ownerProcess != Process.GetCurrentProcess().Id || ownerThread != GetCurrentThreadId())
                throw new InvalidOperationException("Folder selection must run on the owning UI thread.");
            IFileDialog dialog = null;
            IShellItem selected = null;
            IntPtr selectedPath = IntPtr.Zero;
            try {
                dialog = (IFileDialog)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")));
                uint flags;
                dialog.GetOptions(out flags);
                dialog.SetOptions(flags | 0x20u | 0x40u | 0x800u | 0x2000000u); // PICKFOLDERS, FORCEFILESYSTEM, PATHMUSTEXIST, DONTADDTORECENT
                dialog.SetTitle("Select a skill folder containing SKILL.md");
                dialog.SetOkButtonLabel("Select folder");
                int result = dialog.Show(owner);
                if (result == unchecked((int)0x800704C7)) return null;
                Marshal.ThrowExceptionForHR(result);
                dialog.GetResult(out selected);
                selected.GetDisplayName(0x80058000u, out selectedPath); // FILESYSPATH
                return Marshal.PtrToStringUni(selectedPath);
            } finally {
                if (selectedPath != IntPtr.Zero) Marshal.FreeCoTaskMem(selectedPath);
                if (selected != null) Marshal.FinalReleaseComObject(selected);
                if (dialog != null) Marshal.FinalReleaseComObject(dialog);
            }
        }
        [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog {
            [PreserveSig] int Show(IntPtr owner);
            void SetFileTypes(uint count, IntPtr filters);
            void SetFileTypeIndex(uint index);
            void GetFileTypeIndex(out uint index);
            void Advise(IntPtr events, out uint cookie);
            void Unadvise(uint cookie);
            void SetOptions(uint options);
            void GetOptions(out uint options);
            void SetDefaultFolder(IShellItem folder);
            void SetFolder(IShellItem folder);
            void GetFolder(out IShellItem folder);
            void GetCurrentSelection(out IShellItem selection);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
            void GetResult(out IShellItem result);
            void AddPlace(IShellItem item, uint location);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
            void Close(int result);
            void SetClientGuid(ref Guid client);
            void ClearClientData();
            void SetFilter(IntPtr filter);
        }
        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem {
            void BindToHandler(IntPtr context, ref Guid handler, ref Guid iid, out IntPtr result);
            void GetParent(out IShellItem parent);
            void GetDisplayName(uint format, out IntPtr name);
            void GetAttributes(uint mask, out uint attributes);
            void Compare(IShellItem other, uint hint, out int order);
        }
    }
}

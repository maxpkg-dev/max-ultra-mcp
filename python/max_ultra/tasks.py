# Bounded background file work; completion callbacks run only on the caller thread.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from concurrent.futures import ThreadPoolExecutor


class BackgroundTasks:
    def __init__(self):
        self.pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="MaxUltraFiles")
        self.pending = []

    def submit(self, operation, completed, failed):
        if len(self.pending) >= 4:
            raise RuntimeError("File operation queue is busy; wait for the current operation")
        self.pending.append((self.pool.submit(operation), completed, failed))

    def poll(self):
        for entry in list(self.pending):
            future, completed, failed = entry
            if future.done():
                self.pending.remove(entry)
                try:
                    value = future.result()
                except Exception as error:
                    failed(error)
                else:
                    completed(value)

    def close(self):
        for future, _, _ in self.pending:
            future.cancel()
        self.pending.clear()
        self.pool.shutdown(wait=False)

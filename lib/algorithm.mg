// ============================================================================
// Magnetar Standard Library: Algorithms (lib/algorithm.mg)
// Fast search and sort for int arrays and IntList.
// ============================================================================

use "lib/collections.mg";

// -------------------------------------------------------------
// Helpers
// -------------------------------------------------------------
fn algo_swap(int* a, int i, int j) -> void {
    int t = a[i]; a[i] = a[j]; a[j] = t;
}

fn algo_min(int a, int b) -> int { if (a < b) { return a; } return b; }

// -------------------------------------------------------------
// Search - sorted arrays
// -------------------------------------------------------------
fn binary_search(int* arr, int n, int target) -> int {
    int lo = 0; int hi = n - 1;
    while (lo <= hi) {
        int mid = lo + ((hi - lo) / 2);
        int v = arr[mid];
        if (v == target) { return mid; }
        if (v < target) { lo = mid + 1; } else { hi = mid - 1; }
    }
    return 0 - 1;
}

fn lower_bound(int* arr, int n, int target) -> int {
    int lo = 0; int hi = n;
    while (lo < hi) {
        int mid = lo + ((hi - lo) / 2);
        if (arr[mid] < target) { lo = mid + 1; } else { hi = mid; }
    }
    return lo;
}

fn upper_bound(int* arr, int n, int target) -> int {
    int lo = 0; int hi = n;
    while (lo < hi) {
        int mid = lo + ((hi - lo) / 2);
        if (arr[mid] <= target) { lo = mid + 1; } else { hi = mid; }
    }
    return lo;
}

fn linear_search(int* arr, int n, int target) -> int {
    int i = 0;
    while (i < n) { if (arr[i] == target) { return i; } i = i + 1; }
    return 0 - 1;
}

// -------------------------------------------------------------
// IntList search wrappers
// -------------------------------------------------------------
fn intlist_binary_search(IntList* list, int target) -> int {
    return binary_search(list.data, list.length, target);
}
fn intlist_lower_bound(IntList* list, int target) -> int {
    return lower_bound(list.data, list.length, target);
}
fn intlist_upper_bound(IntList* list, int target) -> int {
    return upper_bound(list.data, list.length, target);
}
fn intlist_linear_search(IntList* list, int target) -> int {
    return linear_search(list.data, list.length, target);
}

// -------------------------------------------------------------
// Checks / utilities
// -------------------------------------------------------------
fn is_sorted(int* arr, int n) -> bool {
    int i = 1;
    while (i < n) { if (arr[i - 1] > arr[i]) { return false; } i = i + 1; }
    return true;
}

fn reverse(int* arr, int n) -> void {
    int i = 0; int j = n - 1;
    while (i < j) { algo_swap(arr, i, j); i = i + 1; j = j - 1; }
}

fn intlist_reverse(IntList* list) -> void { reverse(list.data, list.length); }
fn intlist_is_sorted(IntList* list) -> bool { return is_sorted(list.data, list.length); }

// -------------------------------------------------------------
// Insertion sort - small ranges / nearly sorted
// -------------------------------------------------------------
fn insertion_sort_range(int* arr, int lo, int hi) -> void {
    int i = lo + 1;
    while (i <= hi) {
        int key = arr[i];
        int j = i - 1;
        while (j >= lo && arr[j] > key) {
            arr[j + 1] = arr[j];
            j = j - 1;
        }
        arr[j + 1] = key;
        i = i + 1;
    }
}

fn insertion_sort(int* arr, int n) -> void {
    if (n > 1) { insertion_sort_range(arr, 0, n - 1); }
}

// -------------------------------------------------------------
// Heap sort - O(n log n), in-place, no extra memory
// -------------------------------------------------------------
fn _heap_sift_down(int* arr, int start, int end) -> void {
    int root = start;
    while (true) {
        int child = root * 2 + 1;
        if (child > end) { return; }
        int swap_idx = root;
        if (arr[swap_idx] < arr[child]) { swap_idx = child; }
        if (child + 1 <= end && arr[swap_idx] < arr[child + 1]) { swap_idx = child + 1; }
        if (swap_idx == root) { return; }
        algo_swap(arr, root, swap_idx);
        root = swap_idx;
    }
}

fn heap_sort(int* arr, int n) -> void {
    if (n <= 1) { return; }
    int start = (n - 2) / 2;
    while (start >= 0) { _heap_sift_down(arr, start, n - 1); start = start - 1; }
    int end = n - 1;
    while (end > 0) {
        algo_swap(arr, 0, end);
        end = end - 1;
        _heap_sift_down(arr, 0, end);
    }
}

// -------------------------------------------------------------
// Quicksort - iterative, median-of-three, insertion cutoff
// Fast average case, avoids recursion depth issues.
// -------------------------------------------------------------
fn _qs_median3(int* arr, int a, int b, int c) -> int {
    int va = arr[a]; int vb = arr[b]; int vc = arr[c];
    if (va < vb) {
        if (vb < vc) { return b; }
        if (va < vc) { return c; }
        return a;
    } else {
        if (va < vc) { return a; }
        if (vb < vc) { return c; }
        return b;
    }
}

fn _qs_partition(int* arr, int lo, int hi) -> int {
    int mid = lo + ((hi - lo) / 2);
    int piv_idx = _qs_median3(arr, lo, mid, hi);
    int pivot = arr[piv_idx];
    algo_swap(arr, piv_idx, hi);
    int i = lo;
    int j = lo;
    while (j < hi) {
        if (arr[j] < pivot) {
            algo_swap(arr, i, j);
            i = i + 1;
        }
        j = j + 1;
    }
    algo_swap(arr, i, hi);
    return i;
}

fn quick_sort(int* arr, int n) -> void {
    if (n <= 16) { insertion_sort(arr, n); return; }
    int* stack_lo = alloc<int>(64);
    int* stack_hi = alloc<int>(64);
    int sp = 0;
    int cap = 64;
    stack_lo[0] = 0; stack_hi[0] = n - 1; sp = 1;
    while (sp > 0) {
        sp = sp - 1;
        int lo = stack_lo[sp]; int hi = stack_hi[sp];
        while (hi - lo > 16) {
            int p = _qs_partition(arr, lo, hi);
            // push larger side, loop on smaller (keeps stack small)
            int left_sz = p - lo;
            int right_sz = hi - p;
            if (left_sz < right_sz) {
                if (sp >= cap) {
                    int ncap = cap * 2;
                    int* nl = alloc<int>(ncap); int* nh = alloc<int>(ncap);
                    int k = 0; while (k < sp) { nl[k] = stack_lo[k]; nh[k] = stack_hi[k]; k = k + 1; }
                    free(stack_lo); free(stack_hi); stack_lo = nl; stack_hi = nh; cap = ncap;
                }
                stack_lo[sp] = p + 1; stack_hi[sp] = hi; sp = sp + 1;
                hi = p - 1;
            } else {
                if (sp >= cap) {
                    int ncap2 = cap * 2;
                    int* nl2 = alloc<int>(ncap2); int* nh2 = alloc<int>(ncap2);
                    int k2 = 0; while (k2 < sp) { nl2[k2] = stack_lo[k2]; nh2[k2] = stack_hi[k2]; k2 = k2 + 1; }
                    free(stack_lo); free(stack_hi); stack_lo = nl2; stack_hi = nh2; cap = ncap2;
                }
                stack_lo[sp] = lo; stack_hi[sp] = p - 1; sp = sp + 1;
                lo = p + 1;
            }
        }
        if (hi > lo) { insertion_sort_range(arr, lo, hi); }
    }
    free(stack_lo); free(stack_hi);
}

// -------------------------------------------------------------
// Merge sort - stable, O(n log n), uses temp buffer
// -------------------------------------------------------------
fn _merge(int* arr, int* tmp, int lo, int mid, int hi) -> void {
    int i = lo; int j = mid + 1; int k = lo;
    while (i <= mid && j <= hi) {
        if (arr[i] <= arr[j]) { tmp[k] = arr[i]; i = i + 1; }
        else { tmp[k] = arr[j]; j = j + 1; }
        k = k + 1;
    }
    while (i <= mid) { tmp[k] = arr[i]; i = i + 1; k = k + 1; }
    while (j <= hi) { tmp[k] = arr[j]; j = j + 1; k = k + 1; }
    i = lo;
    while (i <= hi) { arr[i] = tmp[i]; i = i + 1; }
}

fn _merge_sort_rec(int* arr, int* tmp, int lo, int hi) -> void {
    if (hi - lo <= 16) { insertion_sort_range(arr, lo, hi); return; }
    int mid = lo + ((hi - lo) / 2);
    _merge_sort_rec(arr, tmp, lo, mid);
    _merge_sort_rec(arr, tmp, mid + 1, hi);
    if (arr[mid] <= arr[mid + 1]) { return; }
    _merge(arr, tmp, lo, mid, hi);
}

fn merge_sort(int* arr, int n) -> void {
    if (n <= 16) { insertion_sort(arr, n); return; }
    int* tmp = alloc<int>(n);
    _merge_sort_rec(arr, tmp, 0, n - 1);
    free(tmp);
}

// -------------------------------------------------------------
// Convenience wrappers
// -------------------------------------------------------------
fn sort(int* arr, int n) -> void { quick_sort(arr, n); }
fn sort_stable(int* arr, int n) -> void { merge_sort(arr, n); }

fn intlist_sort(IntList* list) -> void { if (list.length > 1) { quick_sort(list.data, list.length); } }
fn intlist_sort_stable(IntList* list) -> void { if (list.length > 1) { merge_sort(list.data, list.length); } }
fn intlist_heap_sort(IntList* list) -> void { if (list.length > 1) { heap_sort(list.data, list.length); } }

// Find min/max
fn array_min(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    int m = arr[0]; int i = 1; while (i < n) { if (arr[i] < m) { m = arr[i]; } i = i + 1; } return m;
}
fn array_max(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    int m = arr[0]; int i = 1; while (i < n) { if (arr[i] > m) { m = arr[i]; } i = i + 1; } return m;
}

// -------------------------------------------------------------
// Extra array utilities
// -------------------------------------------------------------
fn fill(int* arr, int n, int value) -> void {
    int i = 0; while (i < n) { arr[i] = value; i = i + 1; }
}

fn copy_array(int* src, int* dst, int n) -> void {
    int i = 0; while (i < n) { dst[i] = src[i]; i = i + 1; }
}

fn count_value(int* arr, int n, int target) -> int {
    int c = 0; int i = 0;
    while (i < n) { if (arr[i] == target) { c = c + 1; } i = i + 1; }
    return c;
}

fn array_equals(int* a, int* b, int n) -> bool {
    int i = 0;
    while (i < n) { if (a[i] != b[i]) { return false; } i = i + 1; }
    return true;
}

fn array_sum(int* arr, int n) -> int {
    int s = 0; int i = 0;
    while (i < n) { s = s + arr[i]; i = i + 1; }
    return s;
}

fn min_index(int* arr, int n) -> int {
    if (n <= 0) { return 0 - 1; }
    int mi = 0; int i = 1;
    while (i < n) { if (arr[i] < arr[mi]) { mi = i; } i = i + 1; }
    return mi;
}

fn max_index(int* arr, int n) -> int {
    if (n <= 0) { return 0 - 1; }
    int mi = 0; int i = 1;
    while (i < n) { if (arr[i] > arr[mi]) { mi = i; } i = i + 1; }
    return mi;
}

fn clamp_int(int v, int lo, int hi) -> int {
    if (v < lo) { return lo; }
    if (v > hi) { return hi; }
    return v;
}

// Remove consecutive duplicates in sorted array, returns new length
fn unique_sorted(int* arr, int n) -> int {
    if (n <= 1) { return n; }
    int w = 1; int i = 1;
    while (i < n) {
        if (arr[i] != arr[w - 1]) { arr[w] = arr[i]; w = w + 1; }
        i = i + 1;
    }
    return w;
}

fn _reverse_range(int* arr, int lo, int hi) -> void {
    while (lo < hi) { int t = arr[lo]; arr[lo] = arr[hi]; arr[hi] = t; lo = lo + 1; hi = hi - 1; }
}

// Rotate left by k positions: [1,2,3,4,5], k=2 -> [3,4,5,1,2]
fn rotate_left(int* arr, int n, int k) -> void {
    if (n <= 1) { return; }
    k = k % n;
    if (k < 0) { k = k + n; }
    if (k == 0) { return; }
    _reverse_range(arr, 0, k - 1);
    _reverse_range(arr, k, n - 1);
    _reverse_range(arr, 0, n - 1);
}

fn rotate_right(int* arr, int n, int k) -> void {
    if (n <= 1) { return; }
    k = k % n;
    if (k < 0) { k = k + n; }
    if (k == 0) { return; }
    rotate_left(arr, n, n - k);
}

// Descending sort: sort then reverse (simple, stable if merge used before; here quick+reverse)
fn quick_sort_desc(int* arr, int n) -> void {
    quick_sort(arr, n);
    reverse(arr, n);
}
fn sort_desc(int* arr, int n) -> void { quick_sort_desc(arr, n); }

// Binary search in descending-sorted array
fn binary_search_desc(int* arr, int n, int target) -> int {
    int lo = 0; int hi = n - 1;
    while (lo <= hi) {
        int mid = lo + ((hi - lo) / 2);
        int v = arr[mid];
        if (v == target) { return mid; }
        if (v > target) { lo = mid + 1; } else { hi = mid - 1; }
    }
    return 0 - 1;
}

// -------------------------------------------------------------
// IntList extras
// -------------------------------------------------------------
fn intlist_count(IntList* list, int target) -> int { return count_value(list.data, list.length, target); }
fn intlist_sum(IntList* list) -> int { return array_sum(list.data, list.length); }
fn intlist_min(IntList* list) -> int { return array_min(list.data, list.length); }
fn intlist_max(IntList* list) -> int { return array_max(list.data, list.length); }
fn intlist_sort_desc(IntList* list) -> void { if (list.length > 1) { quick_sort_desc(list.data, list.length); } }
fn intlist_unique_sorted(IntList* list) -> void { list.length = unique_sorted(list.data, list.length); }
fn intlist_fill(IntList* list, int value) -> void { fill(list.data, list.length, value); }

// -------------------------------------------------------------
// IntList convenience: remove value, push unique, copy
// -------------------------------------------------------------
fn intlist_index_of(IntList* list, int target) -> int { return linear_search(list.data, list.length, target); }
fn intlist_contains(IntList* list, int target) -> bool { return linear_search(list.data, list.length, target) >= 0; }

fn intlist_remove_value(IntList* list, int target) -> bool {
    int idx = linear_search(list.data, list.length, target);
    if (idx < 0) { return false; }
    list.remove_at(idx);
    return true;
}

fn intlist_push_unique(IntList* list, int target) -> bool {
    if (intlist_contains(list, target)) { return false; }
    list.push(target);
    return true;
}

fn intlist_copy(IntList* src, IntList* dst) -> void {
    dst.clear();
    dst.ensure_capacity(src.length);
    int i = 0;
    while (i < src.length) { dst.push(src.get(i)); i = i + 1; }
}

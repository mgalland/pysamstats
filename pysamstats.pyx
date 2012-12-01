# cython: profile=True


import sys
import numpy as np
cimport numpy as np
import time
import csv
from libc.stdint cimport uint32_t
from csamtools cimport bam1_t, bam_pileup1_t, Samfile, PileupProxy


## These are bits set in the flag.
## have to put these definitions here, in csamtools.pxd they got ignored
## @abstract the read is paired in sequencing, no matter whether it is mapped in a pair */
DEF BAM_FPAIRED       =1
## @abstract the read is mapped in a proper pair */
DEF BAM_FPROPER_PAIR  =2
## @abstract the read itself is unmapped; conflictive with BAM_FPROPER_PAIR */
DEF BAM_FUNMAP        =4
## @abstract the mate is unmapped */
DEF BAM_FMUNMAP       =8
## @abstract the read is mapped to the reverse strand */
DEF BAM_FREVERSE      =16
## @abstract the mate is mapped to the reverse strand */
DEF BAM_FMREVERSE     =32
## @abstract this is read1 */
DEF BAM_FREAD1        =64
## @abstract this is read2 */
DEF BAM_FREAD2       =128
## @abstract not primary alignment */
DEF BAM_FSECONDARY   =256
## @abstract QC failure */
DEF BAM_FQCFAIL      =512
## @abstract optical or PCR duplicate */
DEF BAM_FDUP        =1024


def normalise_coords(start, end, one_based):
    if one_based:
        start = start - 1 if start is not None else None
        end = end - 1 if end is not None else None
    return start, end


#############################
# BASIC COVERAGE STATISTICS #
#############################


cpdef object construct_rec_coverage(Samfile samfile, PileupProxy col, bint one_based=False):

    # statically typed variables
    cdef bam_pileup1_t ** plp
    cdef bam_pileup1_t * read
    cdef bam1_t * aln
    cdef int i # loop index
    cdef int n # total number of reads in column
    cdef uint32_t flag
    cdef bint b_is_proper_pair
    cdef unsigned int reads_pp = 0

    # initialise variables
    n = col.n
    plp = col.plp

    # get chromosome name and position
    chrom = samfile.getrname(col.tid)
    pos = col.pos + 1 if one_based else col.pos
    
    # loop over reads, extract what we need
    for i in range(n):
        read = &(plp[0][i])
        aln = read.b
        flag = aln.core.flag
        b_is_proper_pair = flag & BAM_FPROPER_PAIR
        if b_is_proper_pair:
            reads_pp += 1

    return {'chr': chrom, 
            'pos': pos, 
            'reads_all': n, 
            'reads_pp': reads_pp}


def stat_coverage(samfile, chrom=None, start=None, end=None, one_based=False):
    start, end = normalise_coords(start, end, one_based)
    for col in samfile.pileup(chrom, start, end):
        yield construct_rec_coverage(samfile, col, one_based)
        
        
def write_stats(statfun, outfile, fieldnames, samfile,
                dialect=csv.excel_tab, write_header=True, 
                chrom=None, start=None, end=None, 
                one_based=False, progress=None):
    cdef long long counter = 0
    cdef long long modulus
    
    writer = csv.DictWriter(outfile, fieldnames, dialect=dialect)
    
    if write_header:
        writer.writeheader()
    
    if progress is None:
        recs = statfun(samfile, chrom=chrom, start=start, end=end, one_based=one_based)
        writer.writerows(recs)

    else:
        modulus = progress
        before = time.time()
        before_all = before
        for rec in statfun(samfile, chrom=chrom, start=start, end=end, one_based=one_based):
            counter += 1
            writer.writerow(rec)
            if counter % modulus == 0:
                after = time.time()
                elapsed = after - before_all
                batch_elapsed = after - before
                print >>sys.stderr, '%s rows in %.2fs (%d rows/s); batch in %.2fs (%d rows/s)' % (counter, elapsed, counter/elapsed, batch_elapsed, progress/batch_elapsed)
                before = after
        after_all = time.time()
        elapsed_all = after_all - before_all
        print >>sys.stderr, '%s rows in %.2fs (%d rows/s)' % (counter, elapsed_all, counter/elapsed_all)
    
    
def write_coverage(outfile, samfile, dialect=csv.excel_tab, write_header=True,
                   chrom=None, start=None, end=None, 
                   one_based=False, progress=None):
    fieldnames = ('chr', 'pos', 'reads_all', 'reads_pp')
    write_stats(stat_coverage, outfile, fieldnames, samfile, 
                dialect=dialect, write_header=write_header,
                chrom=chrom, start=start, end=end, 
                one_based=one_based, progress=progress)
    
    
################################
# STRANDED COVERAGE STATISTICS #
################################


cpdef object construct_rec_coverage_strand(Samfile samfile, PileupProxy col, bint one_based=False):

    # statically typed variables
    cdef bam_pileup1_t ** plp
    cdef bam_pileup1_t * read
    cdef bam1_t * aln
    cdef int i # loop index
    cdef int n # total number of reads in column
    cdef uint32_t flag
    cdef bint b_is_reverse 
    cdef bint b_is_proper_pair 
    cdef unsigned int reads_fwd = 0
    cdef unsigned int reads_rev = 0
    cdef unsigned int reads_pp = 0
    cdef unsigned int reads_pp_fwd = 0
    cdef unsigned int reads_pp_rev = 0
    
    # initialise variables
    n = col.n
    plp = col.plp

    # get chromosome name and position
    chrom = samfile.getrname(col.tid)
    pos = col.pos + 1 if one_based else col.pos
    
    # loop over reads, extract what we need
    for i in range(n):
        read = &(plp[0][i])
        aln = read.b
        flag = aln.core.flag
        b_is_reverse = flag & BAM_FREVERSE
        if b_is_reverse:
            reads_rev += 1
        else:
            reads_fwd += 1
        b_is_proper_pair = flag & BAM_FPROPER_PAIR
        if b_is_proper_pair:
            reads_pp += 1
            if b_is_reverse:
                reads_pp_rev += 1
            else:
                reads_pp_fwd += 1

    return {'chr': chrom, 
            'pos': pos, 
            'reads_all': n, 
            'reads_fwd': reads_fwd, 
            'reads_rev': reads_rev, 
            'reads_pp': reads_pp,
            'reads_pp_fwd': reads_pp_fwd,
            'reads_pp_rev': reads_pp_rev}


def stat_coverage_strand(samfile, chrom=None, start=None, end=None, one_based=False):
    start, end = normalise_coords(start, end, one_based)
    for col in samfile.pileup(chrom, start, end):
        yield construct_rec_coverage_strand(samfile, col, one_based)
        
        
def write_coverage_strand(outfile, samfile, dialect=csv.excel_tab, write_header=True,
                          chrom=None, start=None, end=None, 
                          one_based=False, progress=None):
    fieldnames = ('chr', 'pos', 
                  'reads_all', 'reads_fwd', 'reads_rev', 
                  'reads_pp', 'reads_pp_fwd', 'reads_pp_rev')
    write_stats(stat_coverage_strand, outfile, fieldnames, samfile, 
                dialect=dialect, write_header=write_header,
                chrom=chrom, start=start, end=end, 
                one_based=one_based, progress=progress)
    
    
################################
# EXTENDED COVERAGE STATISTICS #
################################


cpdef object construct_rec_coverage_ext(Samfile samfile, PileupProxy col, bint one_based=False):

    # statically typed variables
    cdef bam_pileup1_t ** plp
    cdef bam_pileup1_t * read
    cdef bam1_t * aln
    cdef int i # loop index
    cdef int n # total number of reads in column
    # N.B., cython doesn't explicitly support boolean arrays, so we use uint8 here
    cdef np.ndarray[np.uint8_t, ndim=1] is_reverse 
    cdef np.ndarray[np.uint8_t, ndim=1] is_proper_pair
    cdef np.ndarray[np.uint8_t, ndim=1] mate_is_unmapped
    cdef np.ndarray[np.uint8_t, ndim=1] mate_is_reverse
    cdef np.ndarray[np.uint8_t, ndim=1] rnext
    cdef np.ndarray[np.int32_t, ndim=1] tlen 

    # initialise variables
    n = col.n
    plp = col.plp
    is_reverse = np.zeros((n,), dtype=np.uint8)
    is_proper_pair = np.zeros((n,), dtype=np.uint8)
    mate_is_unmapped = np.zeros((n,), dtype=np.uint8)
    mate_is_reverse = np.zeros((n,), dtype=np.uint8)
    rnext = np.zeros((n,), dtype=np.uint8)
    tlen = np.zeros((n,), dtype=np.int32)

    # get chromosome name and position
    tid = col.tid
    chrom = samfile.getrname(tid)
    pos = col.pos + 1 if one_based else col.pos
    
    # loop over reads, extract what we need
    for i in range(n):
        read = &(plp[0][i])
        aln = read.b
        flag = aln.core.flag
        is_reverse[i] = flag & BAM_FREVERSE
        is_proper_pair[i] = flag & BAM_FPROPER_PAIR
        mate_is_unmapped[i] = flag & BAM_FMUNMAP
        rnext[i] = aln.core.mtid
        mate_is_reverse[i] = flag & BAM_FMREVERSE
        tlen[i] = aln.core.isize
        
    # set up various boolean arrays
    is_reverse.dtype = np.bool
    is_forward = ~is_reverse
    is_proper_pair.dtype = np.bool
    mate_is_unmapped.dtype = np.bool
    mate_is_reverse.dtype = np.bool
    mate_is_mapped = ~mate_is_unmapped
    mate_is_other_chr = mate_is_mapped & np.not_equal(rnext, tid)
    mate_is_same_strand = mate_is_mapped & np.equal(is_reverse, mate_is_reverse)
    is_leftmost = tlen > 0
    is_rightmost = tlen < 0
    is_faceaway = mate_is_mapped & ((is_leftmost & is_reverse) | (is_rightmost & is_forward))

    return {'chr': chrom, 
            'pos': pos, 
            'reads_all': n, 
            'reads_pp': np.count_nonzero(is_proper_pair),
            'reads_mate_unmapped': np.count_nonzero(mate_is_unmapped),
            'reads_mate_other_chr': np.count_nonzero(mate_is_other_chr),
            'reads_mate_same_strand': np.count_nonzero(mate_is_same_strand),
            'reads_faceaway': np.count_nonzero(is_faceaway),
            }


def stat_coverage_ext(samfile, chrom=None, start=None, end=None, one_based=False):
    start, end = normalise_coords(start, end, one_based)
    for col in samfile.pileup(chrom, start, end):
        yield construct_rec_coverage_ext(samfile, col, one_based)
        
        
def write_coverage_ext(outfile, samfile, dialect=csv.excel_tab, write_header=True,
                       chrom=None, start=None, end=None, 
                       one_based=False, progress=None):
    fieldnames = ('chr', 'pos', 
                  'reads_all', 'reads_pp', 
                  'reads_mate_unmapped', 
                  'reads_mate_other_chr',
                  'reads_mate_same_strand',
                  'reads_faceaway')
    write_stats(stat_coverage_ext, outfile, fieldnames, samfile, 
                dialect=dialect, write_header=write_header,
                chrom=chrom, start=start, end=end, 
                one_based=one_based, progress=progress)
    
    

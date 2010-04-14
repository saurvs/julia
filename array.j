struct Array[T,ndims] <: Tensor[T,ndims]
    dims::Buffer[Size]
    data::Buffer[T]
end

typealias Vector[T] Tensor[T,1]
typealias Matrix[T] Tensor[T,2]
typealias Indices[T] Union(Range, RangeFrom, RangeBy, RangeTo, Vector[T])

## Basic functions
size(a::Array) = a.dims

size(t::Tensor, d) = size(t)[d]
ndims(t::Tensor) = length(size(t))
numel(t::Tensor) = prod(size(t))
length(v::Vector) = size(v,1)

zeros(T::Type, dims...) = Array[T,length(dims)].new(buffer(dims...), Buffer[T].new(prod(dims)))
zeros(dims...) = zeros(Float64, dims...)

jl_comprehension_zeros (oneresult::Scalar, dims...) = zeros(typeof(oneresult), dims...)

function jl_comprehension_zeros (oneresult, dims...)
    newdims = Buffer[Int32].new(length(dims) + ndims(oneresult))
    for i=1:length(dims); newdims[i] = dims[i]; end
    for i=1:ndims(oneresult); newdims[i+length(dims)] = size(oneresult, i); end
    eltype = typeof(oneresult.data[1])
    data = Buffer[eltype].new(prod(newdims))
    Array[eltype, length(newdims)].new(newdims, data)
end

ones(m::Size) = [ 1.0 | i=1:m ]
ones(m::Size, n::Size) = [ 1.0 | i=1:m, j=1:n ]

rand(m::Size) = [ rand() | i=1:m ]
rand(m::Size, n::Size) = [ rand() | i=1:m, j=1:n ]

(+)(x::Vector, y::Vector) = [ x[i] + y[i] | i=1:length(x) ]
(+)(x::Matrix, y::Matrix) = [ x[i,j] + y[i,j] | i=1:size(x,1), j=1:size(x,2) ]

(.*)(x::Vector, y::Vector) = [ x[i] * y[i] | i=1:length(x) ]

(==)(x::Array, y::Array) = (x.dims == y.dims && x.data == y.data)

transpose(x::Matrix) = [ x[j,i] | i=1:size(x,2), j=1:size(x,1) ]
ctranspose(x::Matrix) = [ conj(x[j,i]) | i=1:size(x,2), j=1:size(x,1) ]

dot(x::Vector, y::Vector) = sum(x.*y)
diag(A::Matrix) = [ A[i,i] | i=1:min(size(A)) ]

(*)(A::Matrix, B::Matrix) = [ dot(A[i,:],B[:,j]) | i=1:size(A,1), j=1:size(B,2) ]

function colon(start::Int32, stop::Int32, stride::Int32)
    len = div((stop-start),stride) + 1
    x = zeros(Int32, len)
    ind = 1
    for i=start:stride:stop
        x[ind] = i
        ind = ind+1
    end
    return x
end

## Indexing: ref()
#TODO: Out-of-bound checks
ref(a::Array, i::Index) = a.data[i]
ref(a::Matrix, i::Index, j::Index) = a.data[(j-1)*a.dims[1] + i]

jl_fill_endpts(A, n, R::RangeBy) = range(1, R.step, size(A, n))
jl_fill_endpts(A, n, R::RangeFrom) = range(R.start, R.step, size(A, n))
jl_fill_endpts(A, n, R::RangeTo) = range(1, R.step, R.stop)
jl_fill_endpts(A, n, R) = R

ref(A::Vector,I) = [ A[i] | i = jl_fill_endpts(A,1,I) ]
ref(A::Matrix,I,J) = [ A[i,j] | i = jl_fill_endpts(A,1,I),
                                j = jl_fill_endpts(A,2,J) ]

ref(A::Matrix,i::Index,J) = [ A[i,j] | j = jl_fill_endpts(A,2,J) ]
ref(A::Matrix,I,j::Index) = [ A[i,j] | i = jl_fill_endpts(A,1,I) ]

function ref(a::Array, I::Index...) 
    data = a.data
    dims = a.dims
    ndims = length(I) - 1

    index = I[1]
    stride = 1
    for k=2:ndims
        stride = stride * dims[k-1]
        index += (I[k]-1) * stride
    end

    return data[index]
end

# Indexing: set()
# TODO: Take care of growing
set(a::Array, x, i::Index) = do (a.data[i] = x, a)
set(a::Matrix, x, i::Index, j::Index) = do (a.data[(j-1)*a.dims[1]+i] = x, a)

function set(a::Array, x, I::Index...)
    # TODO: Need to take care of growing
    data = a.data
    dims = a.dims
    ndims = length(I)

    index = I[1]
    stride = 1
    for k=2:ndims
        stride = stride * dims[k-1]
        index += (I[k]-1) * stride
    end

    data[index] = x
    return a
end

function set(A::Vector, x::Scalar, I)
    I = jl_fill_endpts(A, 1, I)
    for i=I; A[i] = x; end;
    return A
end

function set(A::Vector, X, I)
    I = jl_fill_endpts(A, 1, I)
    count = 1
    for i=I; A[i] = X[count]; count += 1; end
    return A
end

function set(A::Matrix, x::Scalar, I, J)
    I = jl_fill_endpts(A, 1, I)
    J = jl_fill_endpts(A, 2, J)
    for i=I; for j=J; A[i,j] = x; end; end
    return A
end

function set(A::Matrix, X, I, J)
    I = jl_fill_endpts(A, 1, I)
    J = jl_fill_endpts(A, 2, J)
    count = 1
    for i=I; for j=J; A[i,j] = X[count]; count += 1; end; end    
    return A
end

# Concatenation
hcat(X::Scalar...) = [ X[i] | i=1:length(X) ]
vcat(X::Scalar...) = [ X[i] | i=1:length(X) ]
vcat[T](V::Vector[T]...) = [ V[i][j] | i=1:length(V), j=1:length(V[1]) ]
hcat[T](V::Vector[T]...) = [ V[j][i] | i=1:length(V[1]), j=1:length(V) ]

# iterate arrays by iterating data
start(a::Array) = start(a.data)
next(a::Array,i) = next(a.data,i)
done(a::Array,i) = done(a.data,i)

# Print arrays
function print(a::Vector)
    n = a.dims[1]

    if n < 10
        for i=1:n; print(a[i]); if i<n; print("\n"); end; end
    else
        for i=1:3; print(a[i]); print("\n"); end
        print(":\n");
        for i=n-2:n; print(a[i]); if i<n; print("\n"); end; end
    end
end

function printcols(a, start, stop, i)
    for j=start:stop; print(a[i,j]); print(" "); end
end

function print(a::Matrix)

    m = a.dims[1]
    n = a.dims[2]

    print_hdots = false
    print_vdots = false
    if 10 < m; print_vdots = true; end
    if 10 < n; print_hdots = true; end

    if !print_vdots && !print_hdots
        for i=1:m
            printcols(a, 1, n, i)
            if i<m; print("\n"); end
        end
    elseif print_vdots && !print_hdots
        for i=1:3
            printcols(a, 1, n, i)
            print("\n")
        end
        print(":\n")
        for i=m-2:m
            printcols(a, 1, n, i)
            if i<m; print("\n"); end
        end
    elseif !print_vdots && print_hdots
        for i=1:m
            printcols (a, 1, 3, i)
            if i == 1 || i == m; print(": "); else; print("  "); end
            printcols (a, n-2, n, i)
            if i<m; print("\n"); end
        end
    else
        for i=1:3
            printcols (a, 1, 3, i)
            if i == 1; print(": "); else; print("  "); end
            printcols (a, n-2, n, i)
            print("\n")
        end
        print(":\n")
        for i=m-2:m
            printcols (a, 1, 3, i)
            if i == m; print(": "); else; print("  "); end
            printcols (a, n-2, n, i)
            if i<m; print("\n"); end
        end
    end
end # print()

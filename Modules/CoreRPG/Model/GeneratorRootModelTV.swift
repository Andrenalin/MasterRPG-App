// @copyright André Trettin

#if os(tvOS)
/// tvOS has no generator (GeneratorRPG is not built there). This empty stand-in keeps the
/// shared root-model signatures compiling under the real type's name; the real
/// `GeneratorRootModel` (GeneratorRPG) is never built for tvOS, so the names do not meet.
public final class GeneratorRootModel {
    public init () {

    }
}
#endif

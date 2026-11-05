/// Reading content appearance; independent of the transport protocol.
enum ReaderBackground { black, white, theme }

/// Relative page navigation only. Absolute first/last keyboard actions retain
/// their meaning when reversed; disabling presets leaves explicit UI usable.
enum ReaderInputPreset { standard, reversed, disabled }

/// Base image sizing, shared by paged, continuous and enlarged reading.
enum ReaderFit { contain, width, height }

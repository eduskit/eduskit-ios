#if canImport(EduSDKUniffi)
/// 真 UniFFI Core：把生成的 EdusdkClient / InitConfig 等再导出到 EduSDK 模块，
/// 使 Host 源码无需改 import（stub 模式下本文件为空操作）。
@_exported import EduSDKUniffi
#endif

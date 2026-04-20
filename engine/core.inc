#if defined _core_included
  #endinput
#endif
#define _core_included

native heapspace();

native numargs();
native getarg(arg, index=0);
native setarg(arg, index=0, value);

#pragma pack 1

native strlen(const string[]);
native strpack(dest[], const source[]);
native strunpack(dest[], const source[]);

native seed(value);
native random(max);

native min(value1, value2);
native max(value1, value2);
native clamp(value, min=cellmin, max=cellmax);

native print(const string[]);
native printint(value);
native printflt(float:value);
native printf(const string[], ...);


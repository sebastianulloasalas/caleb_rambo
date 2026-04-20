#if defined _math_included
  #endinput
#endif
#define _math_included

#pragma rational float

enum floatround_method {
  floatround_round,
  floatround_floor,
  floatround_ceil
}

native float:float(value);
native float:floatstr(const string[]);
native float:floatmul(float:oper1, float:oper2);
native float:floatdiv(float:dividend, float:divisor);
native float:floatadd(float:dividend, float:divisor);
native float:floatsub(float:oper1, float:oper2);
native float:floatfract(float:value);
native floatround(float:value, floatround_method:method=floatround_round);
native floatcmp(float:fOne, float:fTwo);

native float:operator*(float:oper1, float:oper2) = floatmul;
native float:operator/(float:oper1, float:oper2) = floatdiv;
native float:operator+(float:oper1, float:oper2) = floatadd;
native float:operator-(float:oper1, float:oper2) = floatsub;

stock float:operator++(float:oper)
    return oper+1.0;
stock float:operator--(float:oper)
    return oper-1.0;
stock float:operator-(float:oper)
    return oper^float:0x80000000;
stock float:operator*(float:oper1, oper2)
    return floatmul(oper1, float(oper2));
stock float:operator/(float:oper1, oper2)
    return floatdiv(oper1, float(oper2));
stock float:operator/(oper1, float:oper2)
    return floatdiv(float(oper1), oper2);
stock float:operator+(float:oper1, oper2)
    return floatadd(oper1, float(oper2));
stock float:operator-(float:oper1, oper2)
    return floatsub(oper1, float(oper2));
stock float:operator-(oper1, float:oper2)
    return floatsub(float(oper1), oper2);
stock bool:operator==(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) == 0;
stock bool:operator==(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) == 0;
stock bool:operator!=(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) != 0;
stock bool:operator!=(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) != 0;
stock bool:operator>(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) > 0;
stock bool:operator>(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) > 0;
stock bool:operator>(oper1, float:oper2)
    return floatcmp(float(oper1), oper2) > 0;
stock bool:operator>=(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) >= 0;
stock bool:operator>=(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) >= 0;
stock bool:operator>=(oper1, float:oper2)
    return floatcmp(float(oper1), oper2) >= 0;
stock bool:operator<(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) < 0;
stock bool:operator<(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) < 0;
stock bool:operator<(oper1, float:oper2)
    return floatcmp(float(oper1), oper2) < 0;
stock bool:operator<=(float:oper1, float:oper2)
    return floatcmp(oper1, oper2) <= 0;
stock bool:operator<=(float:oper1, oper2)
    return floatcmp(oper1, float(oper2)) <= 0;
stock bool:operator<=(oper1, float:oper2)
    return floatcmp(float(oper1), oper2) <= 0;
stock bool:operator!(float:oper)
    return floatcmp(oper, 0.0) == 0;

forward operator%(float:oper1, float:oper2);
forward operator%(float:oper1, oper2);
forward operator%(oper1, float:oper2);

native float:abs(float:value);
native float:acos(float:value);
native float:asin(float:value);
native float:atan(float:value);
native float:cos(float:value);
native float:exp(float:value);
native float:log(float:value);
native float:mod(float:oper1,float:oper2);
native float:pow(float:base,float:exp);
native float:sin(float:value);
native float:sqrt(float:value);
native float:tan(float:value);

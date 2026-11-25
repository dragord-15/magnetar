//this is  a libyary for math 
/// all this into int


fn add(int x , int y)-> int{
    return x + y;
}

fn sub(int x , int y)-> int{
    return x - y;
}

fn mul(int x , int y)-> int{
    return x * y;
}

fn div(int x , int y)-> int{
    return x / y;
}


//all this into float 

fn add_float(float x , float y)-> float{
    return x + y;
}

fn sub_float(float x , float y)-> float{
    return x - y;
}

fn mul_float(float x , float y)-> float{
    return x * y;
}

fn div_float(float x , float y)-> float{
    return x / y;
}

// power of number fn 
fn powr(int bas, int expc) -> int {
    if (expc < 0) {
        return 0;   // لا ندعم الأس السالب (يحتاج float)
    }
    if (expc == 0) {
        return 1;
    }
    int result = 1;
    int i = 0;
    while (i < expc) {
        result = result * bas;
        i = i + 1;
    }
    return result;
}

// square root of number fn 

// sqrt للـ int — طريقة نيوتن (بدون float)
fn sqrte(int n) -> int {
    if (n < 0) {
        return 0;   // لا جذر سالب
    }
    if (n == 0) {
        return 0;
    }
    if (n == 1) {
        return 1;
    }

    int x = n;
    int y = (x + 1) / 2;

    // نيوتن: x_{n+1} = (x_n + n/x_n) / 2
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// calcule trigonometric fn 

fn sinn(int deg)->int{
    int tab[19]={        
        0, 87, 174, 259, 342, 423, 500, 574, 643, 707,
        766, 819, 866, 906, 940, 966, 985, 996, 1000};

    int idx = deg /5;
    if (idx > 18) { idx = 18; }
    
    return tab[idx];

}

fn coss(int deg)->int{
    return sinn(90-deg);
}

// تطبيع الزاوية إلى [0, 360)
fn norm_deg(int deg) -> int {
    int d = deg % 360;
    if (d < 0) { d = d + 360; }
    return d;
}

fn sin_deg(int deg) -> int {
    int d = norm_deg(deg);

    // الربع الأول: 0..89 → موجب
    if (d < 90) {
        return sinn(d);
    }
    // الربع الثاني: 90..179 → sin(180-d) موجب
    if (d < 180) {
        return sinn(180 - d);
    }
    // الربع الثالث: 180..269 → -sin(d-180)
    if (d < 270) {
        return -sinn(d - 180);
    }
    // الربع الرابع: 270..359 → -sin(360-d)
    return -sinn(360 - d);
}

fn cos_deg(int deg) -> int {
    int d = norm_deg(deg);

    if (d < 90)  { return coss(d); }
    if (d < 180) { return -coss(180 - d); }
    if (d < 270) { return -coss(d - 180); }
    return coss(360 - d);
}

fn tan_deg(int deg) -> int {
    int s = sin_deg(deg);
    int c = cos_deg(deg);

    // حماية القسمة على صفر
    if (c == 0) {
        if (s > 0) { return 999999; }
        if (s < 0) { return -999999; }
        return 0;
    }
    return (s * 1000) / c;
}



// ============================================================
// cube3d.mg — مكعب ثلاثي الأبعاد يدور في Magnetar v3.5
// ============================================================

// ===== أدوات مثلثية (من math_trig) =====

fn norm_deg(int deg) -> int {
    int d = deg % 360;
    if (d < 0) { d = d + 360; }
    return d;
}

fn sin_q1(int deg) -> int {
    int tab[19] = {
        0, 87, 174, 259, 342, 423, 500, 574, 643, 707,
        766, 819, 866, 906, 940, 966, 985, 996, 1000
    };
    int idx = deg / 5;
    if (idx > 18) { idx = 18; }
    return tab[idx];
}

fn sin_deg(int deg) -> int {
    int d = norm_deg(deg);
    if (d < 90)  { return sin_q1(d); }
    if (d < 180) { return sin_q1(180 - d); }
    if (d < 270) { return -sin_q1(d - 180); }
    return -sin_q1(360 - d);
}

fn cos_deg(int deg) -> int {
    return sin_deg(deg + 90);
}

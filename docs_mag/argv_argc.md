## الاستعمال argv و argc يتوجب عليك اتباع الخطوات هده 


## الخطوة الاولى "استدعاء مكتبة string.mg "
```c
 use "string.mg";
```


## تانيا قم بكتابة الهيكل الخاص بالدالة على هدا الشكل 


```rust

fn main(int argc, char** argv )->int{}

```



## هدا متال على هدا الشرح للقيام بها 


```c

use "string.mg";
use "console.mg";

fn help()-> int {
    print_info("Usage: hello [OPTION]");
    print_info("Options:");
    print_info("  -h, --help    display this help and exit");
    print_info("  -v, --version display version information and exit");
    return 0;
}   

fn version()-> int {
    print("falcon version 0.0.1 \n");
    return 0;
}


fn main(int argc, char** argv) -> int {
    int i = 1;
    while (i < argc) {
        string a = argv[i];
        if (str_equals(a, "--help") || str_equals(a, "-h")) {
            help();
            i=i+1;
            return 0;
        }else if(str_equals(a, "--version") || str_equals(a, "-v")) {
            version();
            i=i+1;
            return 0;
        }else{
            print_error("This command is rang use : -h or --h or -v or --v \n");
            i=i+1;
            return 0;
        }
    }
        
}

```
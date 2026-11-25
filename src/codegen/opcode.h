#ifndef FALCON_OPCODE_H
#define FALCON_OPCODE_H

#include <stdint.h>
#include <stdbool.h>

// ══════════════════════════════════════
// أنواع التعليمات
// ══════════════════════════════════════

typedef enum {
    OP_MOV_RR,      // mov reg, reg
    OP_MOV_RI,      // mov reg, imm
    OP_MOV_RM,      // mov reg, mem
    OP_MOV_MR,      // mov mem, reg
    OP_ADD_RR,      // add reg, reg
    OP_ADD_RI,      // add reg, imm
    OP_SUB_RR,      // sub reg, reg
    OP_SUB_RI,      // sub reg, imm
    OP_IMUL_RR,     // imul reg, reg
    OP_IDIV_R,      // idiv reg
    OP_PUSH_R,      // push reg
    OP_POP_R,       // pop reg
    OP_CALL_R,      // call reg
    OP_CALL_SYM,    // call symbol
    OP_RET,         // ret
    OP_SYSCALL,     // syscall
    OP_JMP,         // jmp
    OP_JE,          // je
    OP_JNE,         // jne
    OP_JL,          // jl
    OP_JG,          // jg
    OP_JLE,         // jle
    OP_JGE,         // jge
    OP_LEA_RR,      // lea reg, [reg+disp]
    OP_LEA_RIP,     // lea reg, [rip+disp]
    OP_CMP_RR,      // cmp reg, reg
    OP_CMP_RI,      // cmp reg, imm
    OP_XOR_RR,      // xor reg, reg
    OP_TEST_RR,     // test reg, reg
    OP_COUNT
} OpcodeType;

// ══════════════════════════════════════
// هيكل التعليمات
// ══════════════════════════════════════

typedef enum {
    OPERAND_NONE,
    OPERAND_REG,
    OPERAND_IMM,
    OPERAND_MEM,
    OPERAND_SYMBOL,
    OPERAND_RIP_REL
} OperandType;

typedef struct {
    OperandType type;
    uint8_t size;       // 1, 2, 4, 8 bytes
    union {
        uint8_t reg;    // register index
        uint64_t imm;   // immediate value
        int32_t disp;   // displacement
        char* symbol;   // symbol name
    };
} Operand;

typedef struct {
    OpcodeType type;
    Operand dst;
    Operand src;
    int line;
    int column;
} Opcode;

// ══════════════════════════════════════
// جدول تشفير التعليمات
// ══════════════════════════════════════

typedef struct {
    uint8_t prefix;          // 0x66, 0xF2, 0xF3...
    uint8_t rex;             // REX prefix
    uint8_t opcode[3];       // opcode bytes
    uint8_t opcode_len;      // number of opcode bytes
    uint8_t modrm_reg;       // reg field in ModRM (for /r)
    bool has_modrm;          // has ModRM byte
    bool has_sib;            // has SIB byte
    bool has_disp;           // has displacement
    bool has_imm;            // has immediate
    uint8_t disp_size;       // 1, 4 bytes
    uint8_t imm_size;        // 1, 2, 4, 8 bytes
} OpcodeEncoding;

// ══════════════════════════════════════
// دوال التشفير
// ══════════════════════════════════════

void opcode_init(void);
OpcodeEncoding* opcode_lookup(OpcodeType type, Operand dst, Operand src);
int opcode_encode(OpcodeEncoding* enc, Operand* dst, Operand* src, uint8_t* buf, int buf_size);

#endif // FALCON_OPCODE_H

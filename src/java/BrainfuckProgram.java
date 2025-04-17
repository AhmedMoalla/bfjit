import java.io.IOException;
import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassModel;
import java.lang.classfile.Label;
import java.lang.classfile.constantpool.ConstantPoolBuilder;
import java.lang.classfile.constantpool.FieldRefEntry;
import java.lang.constant.ClassDesc;
import java.lang.constant.ConstantDesc;
import java.lang.constant.ConstantDescs;
import java.lang.constant.MethodTypeDesc;
import java.nio.file.Files;
import java.nio.file.Paths;

public class Parse {
    public static void main(String[] args) throws IOException {
        ConstantPoolBuilder cpb = ConstantPoolBuilder.of();

        ClassDesc Integer = ClassDesc.of("java.lang.Integer");
        ClassDesc intType = ClassDesc.of("int");
        ClassDesc className = ClassDesc.of("BrainfuckProgram");
        ClassDesc Object = ClassDesc.of("java.lang.Object");
        ClassDesc String = ClassDesc.of("java.lang.String");
        ClassDesc List = ClassDesc.of("java.util.List");
        ClassDesc ArrayList = ClassDesc.of("java.util.ArrayList");

        FieldRefEntry bytes = cpb.fieldRefEntry(cpb.classEntry(className), cpb.nameAndTypeEntry("bytes", List));
        FieldRefEntry head = cpb.fieldRefEntry(cpb.classEntry(className), cpb.nameAndTypeEntry("head", intType));

        byte[] test = ClassFile.of().build(className, b -> {
            b
//                    .withField("head", intType, ClassFile.ACC_PRIVATE)
//                    .withField("bytes", List, ClassFile.ACC_PRIVATE | ClassFile.ACC_FINAL)
//
//                    .withMethod("<init>", MethodTypeDesc.of(ConstantDescs.CD_void), ClassFile.ACC_PUBLIC, mb -> {
//                        mb.withCode(cb -> {
//                            cb.aload(0);
//                            cb.invokespecial(cpb.methodRefEntry(Object, "<init>", MethodTypeDesc.of(ConstantDescs.CD_void)));
//                            cb.aload(0);
//                            cb.new_(ArrayList);
//                            cb.dup();
//                            cb.invokespecial(cpb.methodRefEntry(ArrayList, "<init>", MethodTypeDesc.of(ConstantDescs.CD_void)));
//                            cb.putfield(bytes);
//                            cb.return_();
//                        });
//                    })
//
//                    .withMethod("appendZerosToReachHead", MethodTypeDesc.of(ConstantDescs.CD_void), ClassFile.ACC_PRIVATE, mb -> {
//                        mb.withCode(cb -> {
//                            cb.aload(0);
//                            cb.getfield(head);
//                            cb.aload(0);
//                            cb.getfield(bytes);
//                            cb.invokeinterface(List, "size", MethodTypeDesc.of(ConstantDescs.CD_int));
//
//                            Label endLoop = cb.newLabel();
//                            cb.if_icmplt(endLoop);
//                            cb.aload(0);
//                            cb.getfield(bytes);
//                            cb.iconst_0();
//                            cb.invokestatic(cpb.methodRefEntry(Integer, "valueOf", MethodTypeDesc.of(Integer, intType)));
//                            cb.invokeinterface(List, "add", MethodTypeDesc.of(ClassDesc.of("boolean"), Object));
//                            cb.pop();
//                            cb.goto_(cb.startLabel()).labelBinding(endLoop);
//                            cb.return_();
//                        });
//                    })

                    .withMethod("main", MethodTypeDesc.of(ConstantDescs.CD_void, String.arrayType()),
                            ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, mb -> {
                                mb.withCode(cb -> {
//                                    cb.getstatic(ClassDesc.of("java.lang.System"), "out", ClassDesc.of("java.io.PrintStream"));
//                                    cb.ldc(cpb.stringEntry("Hello World"));
//                                    cb.invokevirtual(cpb.methodRefEntry(ClassDesc.of("java.io.PrintStream"),
//                                            "println", MethodTypeDesc.of(ConstantDescs.CD_void, String)));
                                    cb.return_();
                                });
                            })

                    .withVersion(ClassFile.JAVA_1_VERSION, 0);
        });

        Files.write(Paths.get("C:\\Users\\ahmed\\IdeaProjects\\brainfuck\\BrainfuckProgram.class"), test);

        ClassModel bf1 = ClassFile.of()
                .parse(Paths.get("C:\\Users\\ahmed\\IdeaProjects\\brainfuck\\target\\classes\\BrainfuckProgram2.class"));
//        System.out.println(bf1.toDebugString());
        System.out.println("===============");
        bf1 = ClassFile.of()
                .parse(Paths.get("C:\\Users\\ahmed\\IdeaProjects\\brainfuck\\BrainfuckProgram.class"));
        System.out.println(bf1.toDebugString());

    }
}

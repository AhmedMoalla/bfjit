import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class BrainfuckProgram {
    private static final List<Integer> bytes = new ArrayList<>();
    private static int head;

    public static void incHead(int count) {
        head += count;
        appendZerosToReachHead();
    }

    public static void decHead(int count) {
        if (head < count) {
            throw new RuntimeException("MemoryUnderflow");
        }
        head -= count;
    }

    public static void incAtHead(int count) {
        appendZerosToReachHead();
        Integer currentValue = bytes.get(head);
        bytes.set(head, currentValue + count);
    }

    public static void decAtHead(int count) {
        appendZerosToReachHead();
        Integer currentValue = bytes.get(head);
        bytes.set(head, currentValue - count);
    }

    public static Integer getAtHead() {
        if (head >= bytes.size()) {
            return null;
        }

        return bytes.get(head);
    }

    public static void setAtHead(int value) {
        appendZerosToReachHead();
        bytes.set(head, value);
    }

    private static void appendZerosToReachHead() {
        while (head >= bytes.size()) {
            bytes.add(0);
        }
    }

    private static Integer headValue, nextIn;

    public static void main(String[] args) throws IOException {
        setAtHead(0);
        incAtHead(1);
        decAtHead(1);
        decHead(1);
        incHead(1);
        if ((nextIn = System.in.read()) != -1) {
            setAtHead(nextIn);
        }
        headValue = getAtHead();
        if (headValue != null) {
            System.out.print((char)headValue.intValue());
        }
        while ((headValue = getAtHead()) != null && headValue != 0) {}
    }
}

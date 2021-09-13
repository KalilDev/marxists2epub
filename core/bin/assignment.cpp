#include <array>
#include <vector>
#include <functional>
#include <iostream>
#include <string>
#include <cstddef>
#include <concepts>

const int HASHTABLE_INITIAL_LENGTH = 8;

template <typename T>
concept Hashable = requires(T a)
{
    {
        std::hash<T>{}(a)
    }
    ->std::convertible_to<std::size_t>;
};
template <typename T>
typedef size_tHashFunction(const &T);

template <typename T>
typedef bool EqualityFunction(const &T, const &T);

template <typename T>
struct SinglyLinkedNode
{
    T value;
    LinkedNode<T> next;
}

template <typename T>
struct HashBucket
{
    size_t hashCode;
    SinglyLinkedNode<T> head;
}

template <typename T>
class HashTable
{
public:
    HashTable(T *values[], int length) : m_values(values), m_values_length(length) {}
    HashTable() : m_values(new T[HASHTABLE_INITIAL_LENGTH]) {}
    ~HashTable()
    {
        delete m_values;
        m_values = nullptr;
    }

    void insert(T &value) {}
    T remove(const T &value) {}
    T find(size_t hashCode, std::function<bool(T)> predicate)
    {
        auto i = hashCode % m_values_length;
    }

private:
    T *m_values[];
    int m_values_length;
};

int main()
{
    std::cout << "Hello" << std::endl;

    std::cout << "Goodbye" << std::endl;
    return 0;
}
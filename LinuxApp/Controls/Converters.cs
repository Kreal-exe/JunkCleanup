using System.Globalization;
using Avalonia.Data;
using Avalonia.Data.Converters;
using Avalonia.Media.Transformation;
using JunkCleanup.Core;
using JunkCleanup.ViewModels;
using Material.Icons;

namespace JunkCleanup.Controls;

/// <summary>An icon name from the catalog or a view model ("FolderOutline") as a Material icon.</summary>
public sealed class IconConverter : IValueConverter
{
    public static readonly IconConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Parse(value as string);

    public static MaterialIconKind Parse(string? name)
        => Enum.TryParse<MaterialIconKind>(name, out var kind) ? kind : MaterialIconKind.FolderOutline;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class EqualsConverter : IValueConverter
{
    public static readonly EqualsConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => Equals(value?.ToString(), parameter?.ToString());

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => BindingOperations.DoNothing;
}

public sealed class BytesConverter : IValueConverter
{
    public static readonly BytesConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value switch
    {
        long l => ByteFormatter.Format(l),
        int i => ByteFormatter.Format(i),
        double d => ByteFormatter.Format(d),
        _ => string.Empty,
    };

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>A category or risk level as its colour; ConverterParameter=Soft gives the translucent tile background.</summary>
public sealed class PaletteConverter : IValueConverter
{
    public static readonly PaletteConverter Instance = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var soft = "Soft".Equals(parameter as string, StringComparison.Ordinal);
        return value switch
        {
            TargetCategory c => CategoryColors.Brush(c, soft),
            RiskLevel r => CategoryColors.Brush(r, soft),
            _ => null,
        };
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>The sidebar's sliding indicator: one nav row (48 px) per page.</summary>
public sealed class PageOffsetConverter : IValueConverter
{
    public static readonly PageOffsetConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => TransformOperations.Parse($"translateY({(value is AppPage page ? (int)page * 48 : 0)}px)");

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>True for a size above zero (legend entries of empty bands are hidden).</summary>
public sealed class PositiveConverter : IValueConverter
{
    public static readonly PositiveConverter Instance = new();

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value is long l && l > 0;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

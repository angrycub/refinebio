# Generated by Django 2.0.2 on 2018-09-24 19:23

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('data_refinery_common', '0022_computationalresult_organism_index'),
    ]

    operations = [
        migrations.AlterField(
            model_name='experiment',
            name='source_url',
            field=models.TextField(),
        ),
        migrations.AlterField(
            model_name='originalfile',
            name='source_url',
            field=models.TextField(),
        ),
    ]